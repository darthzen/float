#!/usr/bin/env python3
"""Neural SR for undersampled POTM masters, on the ai/comfyui V100.

Rick's standing rule (2026-07-24): all upscaling is neural inference, never classical
resampling. A master is "undersampled" when its pixel density is below the equirect
target across its assigned fov: need_px = fov_x/360 * 12288; stretch = need_px / width.
Masters with stretch > 1.25 get a RealESRGAN_x4plus pass at
upscale_by = min(4.0, stretch * 1.15), then deepsky_auto.json is repointed at the SR
output so the compose stage samples full density. See SR_BACKEND: the UltimateSDUpscale
recipe this used to run is kept switchable (FLOAT_MASTER_SR=usdu) but is no longer the
default — measured on saturn1 it manufactured 3.6x the edge roughness of a plain
resample, to close a 1.25x shortfall.

Caveat (verify on device): diffusion SR can hallucinate point sources in star fields.
That risk is why the default is now a plain upscaler with no sampler in the loop.

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
POTM = os.path.join(REPO, "Float/Resources/Textures/_raw/potm")
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
                         # Seam fixing OFF: "Band Pass" at denoise 1.0 draws a line
                         # down every tile join — exactly why sky360's refine stopped
                         # using it. Padding/blur widened to soften the per-tile tone
                         # steps it can no longer remove.
                         "mask_blur": 32, "tile_padding": 64,
                         "seam_fix_mode": "None",
                         "seam_fix_denoise": 1.0, "seam_fix_width": 64,
                         "seam_fix_mask_blur": 8, "seam_fix_padding": 16,
                         "force_uniform_tiles": True, "tiled_decode": True,
                         "batch_size": 1}},
        "7": {"class_type": "SaveImage",
              "inputs": {"filename_prefix": out_prefix, "images": ["6", 0]}},
    }


# Which model does the master upscale. Round 7, measured on saturn1:
#   USDU  — UltimateSDUpscale + 4x_NMKD-Siax, seam_fix_mode "Band Pass" @ denoise 1.0.
#           Same recipe that was condemned as the banding source in sky360's refine, and
#           it does the same thing here. Against the ESA original resampled to the SAME
#           output size, USDU's mean |2nd-difference| along Saturn's limb is 7.95 vs
#           2.23 — 3.6x the local roughness, i.e. it MANUFACTURED the staircased limb
#           and ring ringing. It was doing that to close a 1.25x resolution shortfall.
#   esrgan — plain RealESRGAN_x4plus (neural_sr's model, chosen by that module's own A/B)
#           via ImageUpscaleWithModel: one pass, no tiling, no seam fix, nothing to
#           invent edges. x4 then Lanczos DOWN to the needed width — downsampling, so
#           the never-classically-upscale rule is untouched.
SR_BACKEND = os.environ.get("FLOAT_MASTER_SR", "esrgan")


def run_pod_sr_esrgan(pod, src_png, name, upscale_by, out_png):
    """RealESRGAN x4, then Lanczos down to exactly upscale_by."""
    from PIL import Image as _I
    from neural_sr import _run_pod
    with _I.open(src_png) as im:
        w, h = im.size
    tw, th = max(1, round(w * upscale_by)), max(1, round(h * upscale_by))
    with tempfile.TemporaryDirectory() as td:
        big = os.path.join(td, "x4.png")
        _run_pod(pod, src_png, f"master_{name}", big)
        with _I.open(big) as up:
            up = up.convert("RGB")
            if up.size != (tw, th):
                up = up.resize((tw, th), _I.LANCZOS)
            up.save(out_png)


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


def original_for(pid, fetch=True):
    """Archive original behind an already-SR'd master, fetched if it is not on disk.

    Most of these were downloaded, upscaled once, and the original dropped — nine of the
    ten in potm_sr/ have no local source — so re-doing an SR means going back to
    esawebb. potm_manifest.json records the archive URL per id, which is the same place
    the first download came from."""
    for ext in (".tif", ".tiff", ".png", ".jpg"):
        p = os.path.join(POTM, pid + ext)
        if os.path.exists(p):
            return p
    if not fetch:
        return None                     # --dry-run must not pull hundreds of MB
    man_path = os.path.join(POTM, "potm_manifest.json")
    if not os.path.exists(man_path):
        raise RuntimeError(f"no original for {pid} and no potm_manifest.json to fetch it")
    url = next((r["url"] for r in json.load(open(man_path)) if r.get("id") == pid), None)
    if not url:
        raise RuntimeError(f"no original for {pid} and no URL for it in potm_manifest.json")
    dst = os.path.join(POTM, pid + os.path.splitext(url)[1])
    log(f"  {pid}: fetching original {url}")
    tmp = dst + ".part"
    subprocess.run(["curl", "-sfL", "-o", tmp, url], check=True)
    os.replace(tmp, dst)                       # never leave a half file looking complete
    return dst


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--redo", action="store_true",
                    help="re-upscale masters ALREADY in potm_sr/ with the current "
                         "backend, overwriting them in place. Originals are re-fetched "
                         "if missing. deepsky_auto.json is not touched — its rows already "
                         "point at these filenames — so this is safe to run without "
                         "re-pointing anything. Do NOT run it while a re-render is in "
                         "progress: it replaces masters that job is reading.")
    args = ap.parse_args()

    rows = json.load(open(AUTO))
    cands = []
    for r in rows:
        done = r["rel"].startswith("../potm_sr/")
        if done != args.redo:
            continue          # normal: only un-SR'd rows. --redo: only the SR'd ones.
        pid = r["name"].removeprefix("spatial_")
        if args.redo:
            src = original_for(pid, fetch=not args.dry_run)
            if src is None:
                log(f"  {r['name']}: original not on disk — would fetch on a real run")
                continue
        else:
            src = os.path.join(DEEPSKY, r["rel"])
        with Image.open(src) as im:
            w = im.size[0]
        stretch = (r["params"]["fov_x"] / 360 * TARGET_W) / w
        if stretch <= STRETCH_MIN:
            if args.redo:
                # Re-measuring against the real original can show a master never needed
                # SR — potm2508a is 3427px against a 2901px footprint (stretch 0.85), so
                # its potm_sr copy is a diffusion pass at ~1:1: all of the artefacts, none
                # of the resolution. Re-upscaling it would only launder the damage, so say
                # what the actual fix is and leave the file alone.
                log(f"  {r['name']}: stretch {stretch:.2f} <= {STRETCH_MIN} — does NOT "
                    f"need SR. Repoint deepsky_auto.json at ../potm/"
                    f"{os.path.basename(src)} and delete potm_sr/{pid}.png")
            continue
        cands.append((r, src, min(4.0, stretch * 1.15)))       # node max is 4.0
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
            if args.redo or not os.path.exists(out):
                with tempfile.TemporaryDirectory() as td:
                    png = os.path.join(td, f"{pid}.png")
                    open_rgb(src).convert("RGB").save(png)
                    t0 = time.time()
                    # Build beside the target and swap: --redo overwrites a master the
                    # compose stage may be reading, and a partly-written PNG there would
                    # fail a scene mid-render rather than anything obvious.
                    staged = out + ".new"
                    (run_pod_sr_esrgan if SR_BACKEND == "esrgan"
                     else run_pod_sr)(pod, png, pid, factor, staged)
                    os.replace(staged, out)
                with Image.open(out) as im:
                    log(f"  {pid}: SR x{factor:.2f} ({SR_BACKEND}) -> "
                        f"{im.size[0]}x{im.size[1]} ({time.time()-t0:.0f}s)")
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
