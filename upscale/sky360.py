#!/usr/bin/env python3
"""Flat deep-sky masters -> full 360 equirect skies, by diffusion outpaint on the V100.

Rick's directive (2026-07-24, third round of wrap feedback): partial equidistant wraps
(180-270deg) still read as "wider shots", not wraparound. Every deep-sky scene — wide
POTM panoramics AND the hand-tuned masters — becomes a FULL 360 sphere. Immersion and
realistic feel supersede accuracy to the source photo: the sphere beyond the master is
speculative diffusion. Ordering is also his: diffusion first at working res to get the
proportions right and convert to equirect, THEN neural upscale to target res.

Stages (per scene, each cached in _raw/_sky_cache/):
  1. outpaint  — master placed on a 1536x768 2:1 canvas at its natural angular
                 proportions (fov_x of 360 wide, height by aspect), rest masked;
                 RV6.0 inpaint at denoise 1.0 hallucinates the surrounding sky.
  2. seam      — roll 180deg, mirror-blend the (now centered) lon join so it is
                 continuous to the pixel, then repaint that band at LOW denoise to break
                 the mirror symmetry without letting the prompt re-tint it.
  (3. refine   — an UltimateSDUpscale x2 used to sit here. It is off by default and kept
                 only for A/B: it tiled the dark sky into a visible grid. See
                 REFINE_BACKEND.)
Downstream (deepsky_pipeline.compose_sky360): RealESRGAN multi-pass -> 12288x6144, pole
soften, then the ORIGINAL high-res master is re-composited over its footprint so real
detail survives the round-trip through working res.

Seeds are fixed per scene name (crc32) so re-runs reproduce. Both workflows are
mirrored in the ComfyUI web UI (build_sr_wf_ui.py): equirect_360_outpaint,
equirect_360_usdu_refine.
"""
import json
import os
import subprocess
import tempfile
import time
import zlib

import numpy as np
from PIL import Image

from neural_sr import comfy_pod

Image.MAX_IMAGE_PIXELS = None
NS = "ai"
CKPT = "realisticVisionV60B1_v51VAE.safetensors"
SIAX = "4x_NMKD-Siax_200k.pth"
WORK_W, WORK_H = 1536, 768
SEAM_BAND = 256                     # px band mirror-blended + repainted across the lon seam
OUTPAINT_STEPS = 30
OUTPAINT_CFG = 7.0
# Masked-region generation is anchored to an init fill (mirror-tiled + blurred master),
# NOT erased-latent inpainting: pilot round 1, the Phantom Galaxy pano came back as a
# cold dark rectangle floating in hallucinated warm dust — denoise-1.0
# VAEEncodeForInpaint gives diffusion no tonal anchor, so it keyed on the galaxy's
# fire colors instead of its dark sky. Init-anchored denoise keeps the surround
# continuing the master's own palette outward from its actual edges.
OUTPAINT_DENOISE = 0.65             # round 3 (0.85): the prompt's "deep black sky"
                                    # overpowered a fire-colored fill on wall-to-wall
                                    # texture masters (Phantom Galaxy) — the anchor
                                    # must dominate so the surround CONTINUES the
                                    # master's edges; USDU invents the detail
SEAM_DENOISE = 0.40                 # round 6 (was 0.70): the seam band is now continuous
                                    # BY CONSTRUCTION (mirror blend, see _mirror_blend_seam)
                                    # so diffusion only has to break the mirror symmetry.
                                    # At 0.70 the prompt re-tinted the band — on device the
                                    # Phantom Galaxy's warm sky grew a cool purple stripe
                                    # down 180deg that read as a vertical bruise. Measured:
                                    # the R-B axis swung +29 -> -11 -> +5 across the band
                                    # with no pixel-level step, i.e. a palette failure, not
                                    # a continuity failure — so lower the denoise, don't
                                    # widen the mask
FILL_BLUR = 32                      # px, near-rect fill: local continuation structure
FILL_BLUR_FAR = 128                 # px, far-field fill: round 4 left ghost COPIES of
                                    # the master (mirror tiles at blur 32 kept its
                                    # morphology, which denoise 0.65 preserved) — far
                                    # from the rect only a structureless wash remains
GHOST_DIST = 256                    # px over which near fill fades to far fill
FILL_DETAIL = 0.35                  # fraction of the master's FINE texture (detail finer
                                    # than FILL_BLUR) added back into the FAR fill. The
                                    # anchor dominance that fixed the palette problem is
                                    # also what left the far surround a structureless
                                    # wash: at denoise 0.65 diffusion faithfully continues
                                    # a blur-128 anchor, and a blurred anchor produces
                                    # blurred sky. Feeding back the high band only gives
                                    # it something to develop into stars/filaments without
                                    # touching the LOW band, which is where round 4's ghost
                                    # copies of the master lived (morphology coarser than
                                    # FILL_BLUR) — different frequency band, so this does
                                    # not reopen that failure
MASK_BLUR = 24                      # soft mask edge; true master pixels return in the
                                    # final-res re-composite anyway
MASK_OVERLAP = 48                   # px floor for how far the generation ring reaches
                                    # INTO the master; FOOT_FEATHER normally sets it
# How far the master dissolves into the surround, as a fraction of its own footprint.
# This is ONE number used twice and the two uses must agree: build_canvas fades the
# master into the fill over it, and deepsky_pipeline._paste_master fades the true
# high-res master back in over it at final res. If they disagreed you would get real
# detail returning inside a ring the sky had already blurred, i.e. the hard edge back.
# Fields dissolve further (they are meant to read as surrounding cloud, device round 1);
# objects less, so the hero does not lose its own outline.
FOOT_FEATHER = {"field": 0.22, "object": 0.14}
REFINE_DENOISE = 0.30               # higher than SR's 0.20: we WANT invented detail
REFINE_BY = 2.0                     # 1536x768 -> 3072x1536 (then ESRGAN x4 = 12288)

# Which x2 refine sits between the outpaint and the ESRGAN run up to target.
#   "none" (default) — no diffusion refine; neural_sr multi-passes RealESRGAN 1536 -> 12288.
#   "usdu"           — the UltimateSDUpscale pass, kept switchable for A/B only.
# Round 6, on device: USDU is the source of the "banding on pretty much every image"
# report. It tiles a near-flat dark sky and each tile's VAE round-trip lands on its own
# black level, so the 12288 sky carries a visible 1024-tile grid of tone steps; the
# "Band Pass" seam fix then draws a DARK LINE down every tile join at denoise 1.0.
# Confirmed by stage inspection: the 1536 outpaint is clean, the 3072 refine has the grid.
# This is also just neural_sr.py's own A/B finding (RealESRGAN beats USDU on equirect
# starfields, "no tile seams") re-learned the hard way — the refine stage reintroduced
# the loser. The cost of "none" is that the hallucinated surround keeps whatever detail
# the outpaint gave it; invent structure THERE, not in a tiled post-pass.
REFINE_BACKEND = os.environ.get("SKY360_REFINE", "none")

# Bump when a stage's recipe changes. It is part of every cache filename, so a recipe
# change can never silently reuse an old render — the previous round's near-miss was an
# `[or]*` glob that cleared two of a scene's three stage files and left the third.
# Old-tag files are just dead weight in the (gitignored) cache; delete them when happy.
SKY_RECIPE = "r7"

# The field prompt has to ask for CONTINUATION, not surroundings. These masters are
# crops: the subject runs past every frame edge, so "deep space surrounding X" invites
# the model to stop X at the frame and start sky — which is exactly the galaxy-ends-in-
# a-box report on the Phantom Galaxy. Naming the structure that must keep going gives
# the outpaint something to extend.
POS_TMPL = ("seamless 360 degree equirectangular panorama, {desc} continuing outward in "
            "every direction beyond the frame, spiral arms and dust lanes and nebulosity "
            "extending and fading into the distance, vast starfield, tiny distant "
            "background galaxies, photorealistic astrophotography, deep black sky")
# Objects/planets hang on (near-)black: the mirror-tile fill turns into ghost COPIES
# (batch 1: Saturn grew extra planets, Andromeda a twin swirl) and flat dark surrounds
# show USDU tile seams. Their fill is a flat estimate of the master's own border sky,
# denoise high, prompt = starfield — prompt dominance is CORRECT here.
POS_OBJ = ("seamless 360 degree equirectangular deep space starfield surrounding "
           "{desc}, vast field of scattered stars, tiny distant stars, tiny faint "
           "remote background galaxies, deep black sky, photorealistic astrophotography")
OBJ_DENOISE = 0.85
NEG = ("text, watermark, signature, caption, border, frame, vignette, planet earth, "
       "ground, terrain, horizon, people, spacecraft, window, lens flare, blurry, "
       "lowres, jpeg artifacts, oversaturated")
NEG_OBJ = NEG + ", planet, planets, moon, moons, glowing orb, sphere, planetary rings"


def _log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def scene_seed(name):
    return zlib.crc32(name.encode())


def outpaint_wf(canvas_name, mask_name, prompt, seed, out_prefix,
                denoise=OUTPAINT_DENOISE, neg=NEG):
    """API-format init-anchored outpaint: masked region regenerates FROM the canvas's
    blurred fill (VAEEncode + SetLatentNoiseMask), unmasked master stays."""
    return {
        "1": {"class_type": "LoadImage", "inputs": {"image": canvas_name}},
        "2": {"class_type": "LoadImageMask", "inputs": {"image": mask_name, "channel": "red"}},
        "3": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": CKPT}},
        "4": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["3", 1], "text": prompt}},
        "5": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["3", 1], "text": neg}},
        "6": {"class_type": "VAEEncode", "inputs": {"pixels": ["1", 0], "vae": ["3", 2]}},
        "10": {"class_type": "SetLatentNoiseMask",
               "inputs": {"samples": ["6", 0], "mask": ["2", 0]}},
        "7": {"class_type": "KSampler",
              "inputs": {"model": ["3", 0], "positive": ["4", 0], "negative": ["5", 0],
                         "latent_image": ["10", 0], "seed": seed, "steps": OUTPAINT_STEPS,
                         "cfg": OUTPAINT_CFG, "sampler_name": "dpmpp_2m",
                         "scheduler": "karras", "denoise": denoise}},
        "8": {"class_type": "VAEDecode", "inputs": {"samples": ["7", 0], "vae": ["3", 2]}},
        "9": {"class_type": "SaveImage",
              "inputs": {"filename_prefix": out_prefix, "images": ["8", 0]}},
    }


def refine_wf(input_name, prompt, seed, out_prefix):
    """USDU x2 refine — recipe parity with master_sr.py except denoise 0.30 and the
    space prompt (we're inventing detail in hallucinated sky, not preserving a photo)."""
    return {
        "1": {"class_type": "LoadImage", "inputs": {"image": input_name}},
        "2": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": CKPT}},
        "3": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["2", 1], "text": prompt}},
        "4": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["2", 1], "text": NEG}},
        "5": {"class_type": "UpscaleModelLoader", "inputs": {"model_name": SIAX}},
        "6": {"class_type": "UltimateSDUpscale",
              "inputs": {"image": ["1", 0], "model": ["2", 0], "positive": ["3", 0],
                         "negative": ["4", 0], "vae": ["2", 2], "upscale_model": ["5", 0],
                         "upscale_by": REFINE_BY, "seed": seed, "steps": 18, "cfg": 6.0,
                         "sampler_name": "dpmpp_2m", "scheduler": "karras",
                         # Tile settings only matter when SKY360_REFINE=usdu is forced for
                         # an A/B. "Band Pass" at denoise 1.0 was drawing a dark line down
                         # every tile join on dark sky, so seam fixing is off and the
                         # padding/blur are wide enough to soften the per-tile tone steps
                         # it cannot remove. See REFINE_BACKEND for why this is not default.
                         "denoise": REFINE_DENOISE, "mode_type": "Chess",
                         "tile_width": 1024, "tile_height": 1024, "mask_blur": 32,
                         "tile_padding": 64, "seam_fix_mode": "None",
                         "seam_fix_denoise": 1.0, "seam_fix_width": 64,
                         "seam_fix_mask_blur": 8, "seam_fix_padding": 16,
                         "force_uniform_tiles": True, "tiled_decode": True,
                         "batch_size": 1}},
        "7": {"class_type": "SaveImage",
              "inputs": {"filename_prefix": out_prefix, "images": ["6", 0]}},
    }


def _upload(pod, local_path, remote_name):
    subprocess.run(["kubectl", "cp", local_path, f"{NS}/{pod}:/basedir/input/{remote_name}"],
                   check=True)


def _run(pod, wf, tag, out_png, timeout_s=3600):
    """Submit an API workflow, poll the queue to idle, fetch the newest output."""
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as tf:
        json.dump({"prompt": wf}, tf)
        wfp = tf.name
    try:
        subprocess.run(["kubectl", "cp", wfp, f"{NS}/{pod}:/tmp/sky_{tag}.json"], check=True)
    finally:
        os.unlink(wfp)
    r = subprocess.run(["kubectl", "exec", "-n", NS, pod, "--", "bash", "-lc",
                        f"curl -s -m 15 -X POST http://127.0.0.1:8188/prompt "
                        f"-H 'Content-Type: application/json' -d @/tmp/sky_{tag}.json"],
                       capture_output=True, text=True)
    if '"prompt_id"' not in r.stdout:
        raise RuntimeError(f"submit failed for {tag}: {r.stdout[:300]} {r.stderr[:200]}")
    t0 = time.time()
    while time.time() - t0 < timeout_s:
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
                         f"ls -t /basedir/output/{tag}_*.png 2>/dev/null | head -1"],
                        capture_output=True, text=True)
    remote = ls.stdout.strip()
    if not remote:
        raise RuntimeError(f"no output for {tag} (check the pod queue before resubmitting)")
    subprocess.run(["kubectl", "cp", f"{NS}/{pod}:{remote}", out_png], check=True)


def _mirror_map(coords, period):
    """Signed coords mapped onto a mirror-tiled source of size `period`."""
    m = np.mod(coords, 2 * period)
    return np.where(m < period, m, 2 * period - 1 - m)


def _smoothstep(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _mirror_blend_seam(rolled, band=SEAM_BAND):
    """Close the (now centred) lon join BY CONSTRUCTION, before any diffusion touches it.

    Over a band centred on the join, cross-fade each side with the mirror of the other
    side. Weight is exactly 0.5 at the join, so both bounding columns resolve to the same
    average and the join is continuous to the pixel; it decays to 0 at the band edge, so
    the original content returns smoothly. The band is left mirror-symmetric, which the
    following low-denoise pass breaks up — but the palette on each side is the local one,
    which is what a free-prompt band at denoise 0.70 could not guarantee (see SEAM_DENOISE).
    """
    out = rolled.astype(np.float32).copy()
    cx = rolled.shape[1] // 2
    h = band // 2
    w = 0.5 * (1.0 - _smoothstep(np.arange(1, h + 1, dtype=np.float32) / h))   # 0.5 -> 0
    left = out[:, cx - h:cx].copy()
    right = out[:, cx:cx + h].copy()
    wl = w[::-1][None, :, None]                 # left band: weight grows toward the join
    wr = w[None, :, None]                       # right band: weight falls from the join
    out[:, cx - h:cx] = left * (1 - wl) + right[:, ::-1] * wl
    out[:, cx:cx + h] = right * (1 - wr) + left[:, ::-1] * wr
    return np.clip(out + 0.5, 0, 255).astype(np.uint8)


def build_canvas(master_im, fov_x, lat, kind="field"):
    """Place the master on a 2:1 canvas at its natural angular proportions. The rest
    of the canvas is a mirror-tiled + heavily blurred extension of the master — the
    init image that anchors the outpaint to the master's own palette (see
    OUTPAINT_DENOISE note). Returns (canvas u8 HxWx3, mask u8 HxW — 255 = generate,
    soft-edged)."""
    from PIL import ImageFilter
    sw, sh = master_im.size
    wf = int(round(WORK_W * fov_x / 360.0))
    hf = min(int(round(wf * sh / sw)), WORK_H)
    x0 = (WORK_W - wf) // 2
    y0 = int(round(WORK_H * (0.5 - lat / 180.0) - hf / 2))
    y0 = max(0, min(WORK_H - hf, y0))
    small = np.asarray(master_im.resize((wf, hf), Image.LANCZOS), np.uint8)
    if kind == "object":
        # flat fill at the master's own border-sky level — no structure, no ghosts
        ring = np.concatenate([small[:4].reshape(-1, 3), small[-4:].reshape(-1, 3),
                               small[:, :4].reshape(-1, 3), small[:, -4:].reshape(-1, 3)])
        fill = np.broadcast_to(np.median(ring, axis=0).astype(np.uint8),
                               (WORK_H, WORK_W, 3)).copy()
    else:
        tiled = small[np.ix_(_mirror_map(np.arange(WORK_H) - y0, hf),
                             _mirror_map(np.arange(WORK_W) - x0, wf))]
        tiled_im = Image.fromarray(tiled, "RGB")
        near = np.asarray(tiled_im.filter(ImageFilter.GaussianBlur(FILL_BLUR)), np.float32)
        far = np.asarray(tiled_im.filter(ImageFilter.GaussianBlur(FILL_BLUR_FAR)), np.float32)
        dx = np.maximum(np.maximum(x0 - np.arange(WORK_W), np.arange(WORK_W) - (x0 + wf - 1)), 0)
        dy = np.maximum(np.maximum(y0 - np.arange(WORK_H), np.arange(WORK_H) - (y0 + hf - 1)), 0)
        t = np.clip(np.hypot(dx[None, :], dy[:, None]) / GHOST_DIST, 0.0, 1.0)[..., None]
        # Fine texture goes back into the far field only — the near field already carries
        # blur-32 structure; it is the far wash that gives diffusion nothing to work with.
        detail = (np.asarray(tiled_im, np.float32) - near) * FILL_DETAIL
        fill = (near * (1 - t) + (far + detail) * t + 0.5)
        fill = np.clip(fill, 0, 255).astype(np.uint8)
    # Feather the master INTO its own fill rather than butting a hard rect against it.
    # Round 6, on device: a hard rect leaves an edge that NOTHING downstream can remove —
    # the sharp-astrophoto-vs-hallucinated-wash boundary is baked into the sky here, at
    # the outpaint, so feathering the final re-composite just fades true detail back in
    # ON TOP of an edge that is already there. Blending it in over a wide ramp, and
    # letting the generation mask cover that whole ramp, means the density falls off
    # gradually and there is no boundary for USDU/ESRGAN to crisp up later.
    fr = FOOT_FEATHER[kind]
    ax = _smoothstep(np.minimum(np.arange(wf), np.arange(wf)[::-1]) / (fr * wf + 1e-9))
    ay = _smoothstep(np.minimum(np.arange(hf), np.arange(hf)[::-1]) / (fr * hf + 1e-9))
    a = np.minimum(ax[None, :], ay[:, None])[..., None]
    canvas = fill.astype(np.float32)
    rect = canvas[y0:y0 + hf, x0:x0 + wf]
    canvas[y0:y0 + hf, x0:x0 + wf] = rect * (1 - a) + small.astype(np.float32) * a
    canvas = np.clip(canvas + 0.5, 0, 255).astype(np.uint8)
    # Generate everywhere except the core the master fully owns — i.e. the whole feather
    # ring is diffusion's to paint, anchored by the already-smooth blend underneath it.
    ovx = max(MASK_OVERLAP, int(fr * wf))
    ovy = max(MASK_OVERLAP // 2, int(fr * hf))
    mask = np.full((WORK_H, WORK_W), 255, np.uint8)
    mask[y0 + ovy:y0 + hf - ovy, x0 + ovx:x0 + wf - ovx] = 0
    mask = np.asarray(Image.fromarray(mask, "L").filter(ImageFilter.GaussianBlur(MASK_BLUR)), np.uint8)
    return canvas, mask


def make_sky(name, master_im, fov_x, lat, desc, cache_dir, kind="field",
             refine=REFINE_BACKEND):
    """Master (PIL RGB, already rotated) -> full-360 sky PNG path (1536x768 with the
    default `refine="none"`, 3072x1536 with `refine="usdu"`). Each pod stage is cached;
    delete the cache file(s) to force a stage to re-run."""
    os.makedirs(cache_dir, exist_ok=True)
    stem = f"{name}_{SKY_RECIPE}"
    refined = os.path.join(cache_dir, f"{stem}_refined.png")
    if refine == "usdu" and os.path.exists(refined):
        return refined
    prompt = (POS_OBJ if kind == "object" else POS_TMPL).format(desc=desc)
    denoise = OBJ_DENOISE if kind == "object" else OUTPAINT_DENOISE
    neg = NEG_OBJ if kind == "object" else NEG
    seed = scene_seed(name)
    pod = comfy_pod()
    outp = os.path.join(cache_dir, f"{stem}_outpaint.png")
    if not os.path.exists(outp):
        canvas, mask = build_canvas(master_im, fov_x, lat, kind)
        with tempfile.TemporaryDirectory() as td:
            cp, mp = os.path.join(td, "c.png"), os.path.join(td, "m.png")
            Image.fromarray(canvas, "RGB").save(cp)
            Image.fromarray(mask, "L").save(mp)
            _upload(pod, cp, f"sky_{name}_canvas.png")
            _upload(pod, mp, f"sky_{name}_mask.png")
            t0 = time.time()
            o1 = os.path.join(td, "o1.png")
            _run(pod, outpaint_wf(f"sky_{name}_canvas.png", f"sky_{name}_mask.png",
                                  prompt, seed, f"skyout_{name}", denoise=denoise,
                                  neg=neg), f"skyout_{name}", o1)
            _log(f"  {name}: outpaint ({time.time() - t0:.0f}s)")
            # close the lon seam: roll 180deg, mirror-blend the join continuous, repaint
            # the band at low denoise to break the mirror symmetry, roll back
            img = np.asarray(Image.open(o1).convert("RGB"), np.uint8)
            rolled = _mirror_blend_seam(np.roll(img, WORK_W // 2, axis=1))
            from PIL import ImageFilter
            band = np.zeros((WORK_H, WORK_W), np.uint8)
            cx = WORK_W // 2
            band[:, cx - SEAM_BAND // 2: cx + SEAM_BAND // 2] = 255
            band = np.asarray(Image.fromarray(band, "L")
                              .filter(ImageFilter.GaussianBlur(MASK_BLUR)), np.uint8)
            rp, bp = os.path.join(td, "r.png"), os.path.join(td, "b.png")
            Image.fromarray(rolled, "RGB").save(rp)
            Image.fromarray(band, "L").save(bp)
            _upload(pod, rp, f"sky_{name}_rolled.png")
            _upload(pod, bp, f"sky_{name}_band.png")
            t0 = time.time()
            o2 = os.path.join(td, "o2.png")
            _run(pod, outpaint_wf(f"sky_{name}_rolled.png", f"sky_{name}_band.png",
                                  prompt, seed + 1, f"skyseam_{name}",
                                  denoise=SEAM_DENOISE, neg=neg), f"skyseam_{name}", o2)
            img = np.asarray(Image.open(o2).convert("RGB"), np.uint8)
            Image.fromarray(np.roll(img, -(WORK_W // 2), axis=1), "RGB").save(outp)
            _log(f"  {name}: seam close ({time.time() - t0:.0f}s)")
    if refine != "usdu":
        return outp
    _upload(pod, outp, f"sky_{name}_outpaint.png")
    t0 = time.time()
    _run(pod, refine_wf(f"sky_{name}_outpaint.png", prompt, seed + 2,
                        f"skyref_{name}"), f"skyref_{name}", refined)
    _log(f"  {name}: USDU refine x{REFINE_BY:.0f} ({time.time() - t0:.0f}s)")
    return refined
