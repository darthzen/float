#!/usr/bin/env python3
"""Neural SR for undersampled POTM masters, on the ai/comfyui V100.

Rick's standing rule (2026-07-24): all upscaling is neural inference, never classical
resampling. A master is "undersampled" when its pixel density is below the equirect
target across its assigned fov: need_px = fov_x/360 * 12288; stretch = need_px / width.
Masters with stretch > 1.25 get an UltimateSDUpscale pass (Realistic Vision V6.0 +
4x NMKD-Siax — recipe parity with the device-approved Shutterstock upscales) at
upscale_by = min(4.0, stretch * 1.15) [node max 4.0], then deepsky_auto.json
is repointed at the SR output so the compose stage samples full density.

Caveat (verify on device): diffusion SR can hallucinate point sources in star fields.
Denoise 0.20 keeps it conservative; A/B the originals if stars look invented.

Run:  python3 upscale/master_sr.py            # select + SR + repoint, resumable
      python3 upscale/master_sr.py --dry-run  # just list candidates/factors
Then: re-compose the affected scenes:
      python3 upscale/deepsky_pipeline.py --only <scene> --force   (per scene)
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile
import time

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(REPO, "scripts"))
from backdrop_tool import open_rgb                                   # noqa: E402

Image.MAX_IMAGE_PIXELS = None
DEEPSKY = os.path.join(REPO, "Float/Resources/Textures/_raw/deepsky")
SR_DIR = os.path.join(REPO, "Float/Resources/Textures/_raw/potm_sr")
AUTO = os.path.join(HERE, "deepsky_auto.json")
TARGET_W = 12288
STRETCH_MIN = 1.25
NS = "ai"


def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def comfy_pod():
    out = subprocess.run(
        ["kubectl", "get", "pods", "-n", NS, "-l", "app=comfyui", "--no-headers",
         "-o", "custom-columns=:metadata.name"], capture_output=True, text=True)
    return out.stdout.strip().split("\n")[0]


def sr_workflow(input_filename, out_prefix, upscale_by):
    """API-format UltimateSDUpscale graph (params mirror build_wf.py's approved recipe)."""
    return {
        "1": {"class_type": "LoadImage", "inputs": {"image": input_filename}},
        "2": {"class_type": "CheckpointLoaderSimple",
              "inputs": {"ckpt_name": "realisticVisionV60B1_v51VAE.safetensors"}},
        "3": {"class_type": "CLIPTextEncode",
              "inputs": {"clip": ["2", 1], "text":
                         "highly detailed, sharp focus, realistic photograph, natural texture, fine detail"}},
        "4": {"class_type": "CLIPTextEncode",
              "inputs": {"clip": ["2", 1], "text":
                         "blurry, soft, noise, film grain, jpeg artifacts, compression, oversharpened, halo, plastic skin"}},
        "5": {"class_type": "UpscaleModelLoader", "inputs": {"model_name": "4x_NMKD-Siax_200k.pth"}},
        "6": {"class_type": "UltimateSDUpscale",
              "inputs": {"image": ["1", 0], "model": ["2", 0], "positive": ["3", 0],
                         "negative": ["4", 0], "vae": ["2", 2], "upscale_model": ["5", 0],
                         "upscale_by": upscale_by, "seed": 0, "steps": 18, "cfg": 6.0,
                         "sampler_name": "dpmpp_2m", "scheduler": "karras", "denoise": 0.20,
                         "mode_type": "Chess", "tile_width": 1024, "tile_height": 1024,
                         "mask_blur": 16, "tile_padding": 32, "seam_fix_mode": "Band Pass",
                         "seam_fix_denoise": 1.0, "seam_fix_width": 64,
                         "seam_fix_mask_blur": 8, "seam_fix_padding": 16,
                         "force_uniform_tiles": True, "tiled_decode": True,
                         "batch_size": 1}},
        "7": {"class_type": "SaveImage",
              "inputs": {"filename_prefix": out_prefix, "images": ["6", 0]}},
    }


def run_pod_sr(pod, src_png, name, upscale_by, out_png):
    subprocess.run(["kubectl", "cp", src_png, f"{NS}/{pod}:/basedir/input/sr_{name}.png"], check=True)
    wf = {"prompt": sr_workflow(f"sr_{name}.png", f"srout_{name}", round(upscale_by, 2))}
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as tf:
        json.dump(wf, tf)
        wfp = tf.name
    try:
        subprocess.run(["kubectl", "cp", wfp, f"{NS}/{pod}:/tmp/sr_{name}.json"], check=True)
    finally:
        os.unlink(wfp)
    r = subprocess.run(["kubectl", "exec", "-n", NS, pod, "--", "bash", "-lc",
                        f"curl -s -m 15 -X POST http://127.0.0.1:8188/prompt "
                        f"-H 'Content-Type: application/json' -d @/tmp/sr_{name}.json"],
                       capture_output=True, text=True)
    if '"prompt_id"' not in r.stdout:
        raise RuntimeError(f"SR submit failed for {name}: {r.stdout[:300]} {r.stderr[:200]}")
    for _ in range(900):                                   # up to ~60 min per image
                                                           # (a 10k-wide USDU output
                                                           # legitimately runs >16 min)
        q = subprocess.run(["kubectl", "exec", "-n", NS, pod, "--", "bash", "-lc",
                            "curl -s -m 6 http://127.0.0.1:8188/queue"],
                           capture_output=True, text=True)
        try:
            d = json.loads(q.stdout)
            if len(d.get("queue_running", [])) + len(d.get("queue_pending", [])) == 0:
                break
        except Exception:
            pass
        time.sleep(4)
    ls = subprocess.run(["kubectl", "exec", "-n", NS, pod, "--", "bash", "-lc",
                         f"ls -t /basedir/output/srout_{name}_*.png 2>/dev/null | head -1"],
                        capture_output=True, text=True)
    remote = ls.stdout.strip()
    if not remote:
        raise RuntimeError(f"no SR output for {name}")
    subprocess.run(["kubectl", "cp", f"{NS}/{pod}:{remote}", out_png], check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    rows = json.load(open(AUTO))
    cands = []
    for r in rows:
        if r["rel"].startswith("../potm_sr/"):
            continue                                        # already repointed
        src = os.path.join(DEEPSKY, r["rel"])
        with Image.open(src) as im:
            w = im.size[0]
        stretch = (r["params"]["fov_x"] / 360 * TARGET_W) / w
        if stretch > STRETCH_MIN:
            cands.append((r, src, min(4.0, stretch * 1.15)))   # node max is 4.0
    log(f"{len(cands)} undersampled master(s)")
    for r, src, f in cands:
        log(f"  {r['name']}: x{f:.2f}")
    if args.dry_run or not cands:
        return 0

    pod = comfy_pod()
    if not pod:
        raise SystemExit("no comfyui pod found")
    log(f"pod: {pod}")
    os.makedirs(SR_DIR, exist_ok=True)
    ok = fail = 0
    for r, src, factor in cands:
        pid = r["name"].removeprefix("spatial_")
        out = os.path.join(SR_DIR, f"{pid}.png")
        try:
            if not os.path.exists(out):
                with tempfile.TemporaryDirectory() as td:
                    png = os.path.join(td, f"{pid}.png")
                    open_rgb(src).convert("RGB").save(png)
                    t0 = time.time()
                    run_pod_sr(pod, png, pid, factor, out)
                with Image.open(out) as im:
                    log(f"  {pid}: SR x{factor:.2f} -> {im.size[0]}x{im.size[1]} ({time.time()-t0:.0f}s)")
            else:
                log(f"  {pid}: SR output exists, skipping pod run")
            r["rel"] = f"../potm_sr/{pid}.png"
            ok += 1
        except Exception as e:                              # noqa: BLE001
            fail += 1
            log(f"  !! FAILED {pid}: {e}")

    with open(AUTO, "w") as f:
        json.dump(rows, f, indent=1)
    log(f"DONE: {ok} SR'd + repointed, {fail} failed. Re-compose with deepsky_pipeline --force.")
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
