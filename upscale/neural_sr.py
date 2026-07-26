#!/usr/bin/env python3
"""Plain-model neural SR on the ai/comfyui V100, for equirect sources below target res.

Rick's standing rule: sources below target are ALWAYS upscaled by neural inference —
there is no "never upscale past the source" (that uninvited cap caused the grainy
SPHEREx scenes). Model choice is whatever gives the best result; for equirect
starfield/all-sky sources that is RealESRGAN_x4plus by A/B (2026-07-24, vs NMKD-Siax /
UltraSharp / UltimateSDUpscale): faithful color on diffuse nebulosity (USDU shifts
hue + speckles), round clean stars (Siax/UltraSharp turn survey noise into worm
artifacts), no tile seams, and ~100x faster than diffusion. The USDU diffusion recipe
remains the choice for flat POTM masters (master_sr.py, device-approved parity).

Equirects are wrap-padded before SR so the lon +/-180 seam (directly behind the
viewer) stays continuous, then cropped back after the model pass. Downscaling to the
exact target after the 4x model pass is Lanczos — the rule governs upscaling only.

The workflow is mirrored in the ComfyUI web UI as "equirect_realesrgan_sr" for study.
"""
import json
import os
import subprocess
import tempfile
import time

from PIL import Image

Image.MAX_IMAGE_PIXELS = None
NS = "ai"
MODEL = "RealESRGAN_x4plus.pth"
MODEL_SCALE = 4
WRAP_PAD = 64                       # px of left/right wrap context fed to the model


def _log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def comfy_pod():
    out = subprocess.run(
        ["kubectl", "get", "pods", "-n", NS, "-l", "app=comfyui", "--no-headers",
         "-o", "custom-columns=:metadata.name"], capture_output=True, text=True)
    pod = out.stdout.strip().split("\n")[0]
    if not pod:
        raise RuntimeError("no comfyui pod found (is Ollama holding the GPU? check replicas)")
    return pod


def _workflow(input_filename, out_prefix):
    return {
        "1": {"class_type": "LoadImage", "inputs": {"image": input_filename}},
        "2": {"class_type": "UpscaleModelLoader", "inputs": {"model_name": MODEL}},
        "3": {"class_type": "ImageUpscaleWithModel",
              "inputs": {"upscale_model": ["2", 0], "image": ["1", 0]}},
        "4": {"class_type": "SaveImage",
              "inputs": {"filename_prefix": out_prefix, "images": ["3", 0]}},
    }


def _run_pod(pod, local_png, tag, out_png, timeout_s=1800):
    subprocess.run(["kubectl", "cp", local_png, f"{NS}/{pod}:/basedir/input/nsr_{tag}.png"],
                   check=True)
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as tf:
        json.dump({"prompt": _workflow(f"nsr_{tag}.png", f"nsrout_{tag}")}, tf)
        wfp = tf.name
    try:
        subprocess.run(["kubectl", "cp", wfp, f"{NS}/{pod}:/tmp/nsr_{tag}.json"], check=True)
    finally:
        os.unlink(wfp)
    before = {l.strip() for l in subprocess.run(
        ["kubectl", "exec", "-n", NS, pod, "--", "bash", "-lc",
         f"ls /basedir/output/nsrout_{tag}_*.png 2>/dev/null"],
        capture_output=True, text=True).stdout.splitlines() if l.strip()}
    r = subprocess.run(["kubectl", "exec", "-n", NS, pod, "--", "bash", "-lc",
                        f"curl -s -m 15 -X POST http://127.0.0.1:8188/prompt "
                        f"-H 'Content-Type: application/json' -d @/tmp/nsr_{tag}.json"],
                       capture_output=True, text=True)
    if '"prompt_id"' not in r.stdout:
        raise RuntimeError(f"SR submit failed for {tag}: {r.stdout[:300]} {r.stderr[:200]}")
    # Wait for a NEW file under this tag rather than for the queue to read idle. The
    # queue can report empty before ComfyUI registers a just-POSTed prompt, and the old
    # code then took `ls -t | head -1` — the PREVIOUS run's upscale for this exact tag,
    # silently, in about a second. Third instance of this pattern (see sky360._run and
    # process_backdrops.depth_via_comfy); this is the worst-placed of the three because
    # sr_equirect runs on EVERY scene and the tags (`<scene>_sky_p0`) accumulate output
    # files across every previous render, so there is always a stale file ready to be
    # picked up. Requiring an unseen filename makes that impossible rather than unlikely.
    def listing():
        r = subprocess.run(["kubectl", "exec", "-n", NS, pod, "--", "bash", "-lc",
                            f"ls /basedir/output/nsrout_{tag}_*.png 2>/dev/null"],
                           capture_output=True, text=True)
        return {l.strip() for l in r.stdout.splitlines() if l.strip()}

    t0 = time.time()
    remote = ""
    while time.time() - t0 < timeout_s:
        time.sleep(4)
        fresh = sorted(listing() - before)
        if fresh:
            remote = fresh[-1]
            q = subprocess.run(["kubectl", "exec", "-n", NS, pod, "--", "bash", "-lc",
                                "curl -s -m 6 http://127.0.0.1:8188/queue"],
                               capture_output=True, text=True)
            try:
                d = json.loads(q.stdout)
                if len(d.get("queue_running", [])) + len(d.get("queue_pending", [])) == 0:
                    break
            except Exception:
                break
    if not remote:
        raise RuntimeError(f"no NEW SR output for {tag} after {time.time() - t0:.0f}s")
    subprocess.run(["kubectl", "cp", f"{NS}/{pod}:{remote}", out_png], check=True)


def _sr_pass(im, tag):
    """One wrap-padded RealESRGAN x4 pass over a PIL equirect. Returns a PIL Image."""
    import numpy as np
    arr = np.asarray(im.convert("RGB"))
    padded = np.concatenate([arr[:, -WRAP_PAD:], arr, arr[:, :WRAP_PAD]], axis=1)
    pod = comfy_pod()
    with tempfile.TemporaryDirectory() as td:
        src = os.path.join(td, "in.png")
        out = os.path.join(td, "out.png")
        Image.fromarray(padded, "RGB").save(src)
        t0 = time.time()
        _run_pod(pod, src, tag, out)
        up = Image.open(out).convert("RGB")
        _log(f"  SR {tag}: {im.size[0]}x{im.size[1]} -> {up.size[0]}x{up.size[1]} "
             f"({MODEL}, {time.time() - t0:.0f}s)")
        pad = WRAP_PAD * MODEL_SCALE
        return up.crop((pad, 0, up.size[0] - pad, up.size[1]))


def sr_equirect(im, tag, target_w):
    """Upscale a PIL equirect to exactly (target_w, target_w//2), wrap-padded across the
    lon seam so +/-180 (directly behind the viewer) stays continuous.

    Multi-pass when one x4 undershoots: the sky360 diffusion canvas is 1536 wide and the
    target is 12288, so it needs x8. Between passes the frame is Lanczos-shrunk to
    target/4 so the FINAL x4 lands exactly on target — otherwise the last pass would have
    to produce (and kubectl cp) a 300-megapixel intermediate. Sources that already reach
    target/4 in one pass behave exactly as before (single pass, then Lanczos down)."""
    n = 0
    while im.width * MODEL_SCALE < target_w:
        im = _sr_pass(im, f"{tag}_p{n}")
        n += 1
        if im.width * MODEL_SCALE > target_w:      # another full pass would overshoot
            im = im.resize((target_w // MODEL_SCALE, target_w // (2 * MODEL_SCALE)),
                           Image.LANCZOS)
    up = _sr_pass(im, f"{tag}_p{n}" if n else tag)
    if up.size != (target_w, target_w // 2):
        up = up.resize((target_w, target_w // 2), Image.LANCZOS)
    return up
