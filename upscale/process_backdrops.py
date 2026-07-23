#!/usr/bin/env python3
"""Batch: every backdrop -> upscaled mono -> depth -> stereo -> spatial HEIC + thumbnail.

The one command that turns the whole library into the app's spatial format. Resumable
(skips finished scenes), one manifest row per scene.

Per scene:
  1. mono_hires  — re-ingest from the highest-res _raw source at TARGET res (this is the
                   "upscale": native source headroom, not diffusion — 23-26K ESO / 12-15K
                   Shutterstock down to 12288; HDRs/8K sources stay at their native cap).
  2. depth       — grounded: Depth Anything V2 on the V100 via the ai/comfyui pod
                   (low-freq, run at 2048 and upsampled in synth). deep-space: luminance.
  3. stereo      — stereo_synth (guided depth-edge + forward warp), baseline 1.0% (§9).
  4. pack        — pack_spatial.swift -> Backdrop/spatial_<name>.heic (2-image, app reads by index)
  5. thumbnail   — left eye -> Backdrop/Thumbnails/<name>.jpg (512w, for the selector)

Run:  python3 upscale/process_backdrops.py            # all, resumable
      python3 upscale/process_backdrops.py --only spatial_dual_nebula
"""
import argparse
import os
import subprocess
import sys
import tempfile
import time

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)                                 # stereo_synth.py
sys.path.insert(0, os.path.join(REPO, "scripts"))        # backdrop_tool.py
from backdrop_tool import load_linear, tonemap                      # noqa: E402
from stereo_synth import synth                                       # noqa: E402

Image.MAX_IMAGE_PIXELS = None
RAW = os.path.join(REPO, "Float/Resources/Textures/_raw")
BACKDROP = os.path.join(REPO, "Float/Resources/Textures/Backdrop")
THUMBS = os.path.join(BACKDROP, "Thumbnails")
DEPTH_CACHE = os.path.join(RAW, "spatial_test")   # reuse existing rogland/paranal depth maps
TARGET_W, TARGET_H = 12288, 6144
BASELINE = 0.010
NS = "ai"

# scene name -> (source relpath under _raw, category, hdr_exposure or None)
MANIFEST = [
    # ── grounded (DA V2 depth) ───────────────────────────────────────────────
    ("spatial_rogland_night",   "grounded/rogland_clear_night_8k.hdr",          "grounded", -3.0),
    ("spatial_dikhololo_night", "grounded/dikhololo_night_8k.hdr",              "grounded", -1.0),
    ("spatial_paranal_vlt",     "grounded/paranal_vlt_milkyway_cabral09_26k.jpg", "grounded", None),
    ("spatial_paranal_lasers",  "grounded/paranal_vlt_milkyway_cabral10_26k.jpg", "grounded", None),
    ("spatial_lasilla_arc",     "grounded/lasilla_milkyway_arc_2019_23k.jpg",   "grounded", None),
    ("spatial_lasilla_airglow", "grounded/lasilla_extra_airglow_2019_24k.jpg",  "grounded", None),
    # ── deep-space (luminance depth) ─────────────────────────────────────────
    ("spatial_dual_nebula",     "shutterstock_2436644261.jpg", "deepspace", None),
    ("spatial_blue_filaments",  "shutterstock_2572761365.jpg", "deepspace", None),
    ("spatial_teal_orange",     "shutterstock_2626369537.jpg", "deepspace", None),
    ("spatial_dark_dust",       "shutterstock_2651221149.jpg", "deepspace", None),
    ("spatial_pale_haze",       "shutterstock_2700631105.jpg", "deepspace", None),
    ("spatial_deep_star_map",   "starmap_2020_8k.exr",         "deepspace", None),
]


def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def comfy_pod():
    p = "/tmp/comfy_pod.txt"
    if os.path.exists(p):
        n = open(p).read().strip()
        if n:
            return n
    out = subprocess.run(
        ["kubectl", "get", "pods", "-n", NS, "-l", "app=comfyui", "--no-headers",
         "-o", "custom-columns=:metadata.name"], capture_output=True, text=True)
    return out.stdout.strip().split("\n")[0]


def mono_hires(src_rel, exposure, out_png):
    """Highest-res source -> tonemapped mono PNG at TARGET res (the 'upscale')."""
    src = os.path.join(RAW, src_rel)
    if src.lower().endswith(".exr"):
        # OpenEXR is NOT Radiance .hdr — load_linear's RGBE parser can't read it. Let
        # ImageIO (sips) do the HDR->display tonemap+decode, then treat it as a normal image.
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tf:
            tmp = tf.name
        try:
            subprocess.run(["sips", "-s", "format", "png", src, "--out", tmp],
                           check=True, capture_output=True)
            im = Image.open(tmp).convert("RGB").copy()
        finally:
            os.unlink(tmp)
    else:
        lin = load_linear(src)
        rgb = tonemap(lin, exposure=exposure or 0.0)
        im = Image.fromarray(rgb, "RGB")
    # never upscale past the source; cap at TARGET. Keeps 8K sources at 8K (no fakery).
    sw = im.size[0]
    w = min(TARGET_W, sw)
    h = w // 2
    if im.size != (w, h):
        im = im.resize((w, h), Image.LANCZOS)
    im.save(out_png)
    return im.size


def depth_via_comfy(mono_png, name, out_png):
    """DA V2 depth on the V100. Feeds a 2048-wide copy (depth is low-frequency)."""
    pod = comfy_pod()
    with tempfile.TemporaryDirectory() as td:
        small = os.path.join(td, f"{name}.png")
        im = Image.open(mono_png).convert("RGB")
        im.resize((2048, 1024), Image.LANCZOS).save(small)
        subprocess.run(["kubectl", "cp", small, f"{NS}/{pod}:/basedir/input/{name}.png"], check=True)
        wf = os.path.join(td, "wf.json")
        subprocess.run([sys.executable, os.path.join(HERE, "build_depth_wf.py"),
                        f"{name}.png", f"depth_{name}"], stdout=open(wf, "w"), check=True)
        subprocess.run(["kubectl", "cp", wf, f"{NS}/{pod}:/tmp/wf_{name}.json"], check=True)
        r = subprocess.run(["kubectl", "exec", "-n", NS, pod, "--", "bash", "-lc",
                            f"curl -s -m 15 -X POST http://127.0.0.1:8188/prompt "
                            f"-H 'Content-Type: application/json' -d @/tmp/wf_{name}.json"],
                           capture_output=True, text=True)
        if '"prompt_id"' not in r.stdout:
            raise RuntimeError(f"depth submit failed for {name}: {r.stdout} {r.stderr}")
        for _ in range(120):
            q = subprocess.run(["kubectl", "exec", "-n", NS, pod, "--", "bash", "-lc",
                                "curl -s -m 6 http://127.0.0.1:8188/queue"], capture_output=True, text=True)
            try:
                import json
                d = json.loads(q.stdout)
                if len(d.get("queue_running", [])) + len(d.get("queue_pending", [])) == 0:
                    break
            except Exception:
                pass
            time.sleep(4)
        # newest matching output
        ls = subprocess.run(["kubectl", "exec", "-n", NS, pod, "--", "bash", "-lc",
                             f"ls -t /basedir/output/depth_{name}_*.png 2>/dev/null | head -1"],
                            capture_output=True, text=True)
        remote = ls.stdout.strip()
        if not remote:
            raise RuntimeError(f"no depth output for {name}")
        subprocess.run(["kubectl", "cp", f"{NS}/{pod}:{remote}", out_png], check=True)


def synth_pack(mono_png, depth_png, name, category):
    # Per-category stereo recipe (§9). Grounded: real DA V2 depth, 1.0% baseline (approved
    # on device), guided edge-snap. Deep-space: near-UNIFORM vergence (high depth floor +
    # heavy smoothing + gentle baseline) so the whole starfield shifts together and fuses like
    # the imported skies — per-feature luminance depth made stars "wildly different". Both use
    # the cos^2 pole falloff so looking up doesn't converge overhead (the zenith artifact).
    #
    # Deep-space tuning (device feedback, two rounds): the first uniform-vergence pass fused
    # well but the nebula relief cardboarded — bright masses popped onto a discrete near plane
    # sitting too close. Progressively flattened: floor 0.75→0.88→0.94 (shrinks near/far
    # separation to ~1.6px), baseline 0.30→0.22%, smoothing 0.03→0.07 (masses blend into a
    # continuous gradient, not layers). Kept a whisper of relief rather than going fully flat,
    # since the depth itself reads well — it was only the layering that was too strong.
    if category == "grounded":
        params = dict(baseline_frac=0.010, smooth_frac=0.0, pole_power=2.0, depth_floor=0.0)
    else:
        params = dict(baseline_frac=0.0022, smooth_frac=0.07, pole_power=2.0, depth_floor=0.94)
    with tempfile.TemporaryDirectory() as td:
        lp0, rp0 = synth(mono_png, depth_png, td, **params)
        lp, rp = lp0, rp0
        out = os.path.join(BACKDROP, f"{name}.heic")
        subprocess.run(["swift", os.path.join(HERE, "pack_spatial.swift"), lp, rp, out], check=True)
        # thumbnail from left eye
        os.makedirs(THUMBS, exist_ok=True)
        th = Image.open(lp).convert("RGB")
        th.thumbnail((512, 256), Image.LANCZOS)
        th.save(os.path.join(THUMBS, f"{name}.jpg"), quality=85)
    return out


def process(name, src_rel, category, exposure, force):
    out = os.path.join(BACKDROP, f"{name}.heic")
    if os.path.exists(out) and not force:
        log(f"skip {name} (exists)")
        return
    log(f"=== {name} ({category}) ===")
    with tempfile.TemporaryDirectory() as td:
        mono = os.path.join(td, "mono.png")
        size = mono_hires(src_rel, exposure, mono)
        log(f"  mono {size[0]}x{size[1]}")
        depth_png = None
        if category == "grounded":
            # reuse an already-computed depth if present, else run DA V2
            cached = {
                "spatial_rogland_night": os.path.join(DEPTH_CACHE, "rogland_depth.png"),
                "spatial_paranal_vlt":   os.path.join(DEPTH_CACHE, "paranal_depth.png"),
            }.get(name)
            depth_png = os.path.join(td, "depth.png")
            if cached and os.path.exists(cached):
                Image.open(cached).save(depth_png)
                log("  depth: cached DA V2")
            else:
                depth_via_comfy(mono, name, depth_png)
                log("  depth: DA V2 (comfyui/V100)")
        else:
            log("  depth: luminance")
        synth_pack(mono, depth_png, name, category)
    mb = os.path.getsize(out) / 1e6
    log(f"  -> {name}.heic ({mb:.1f} MB) + thumbnail")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", help="process just this scene name")
    ap.add_argument("--force", action="store_true", help="re-process even if output exists")
    args = ap.parse_args()
    rows = [r for r in MANIFEST if not args.only or r[0] == args.only]
    log(f"processing {len(rows)} scene(s) -> {TARGET_W}x{TARGET_H} stereo @ {BASELINE:.1%}")
    ok, fail = 0, 0
    for name, src, cat, exp in rows:
        try:
            process(name, src, cat, exp, args.force)
            ok += 1
        except Exception as e:                                       # noqa: BLE001
            fail += 1
            log(f"  !! FAILED {name}: {e}")
    log(f"DONE: {ok} ok, {fail} failed")
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
