#!/usr/bin/env python3
"""Deep-sky masters -> spatial scene HEICs, via gnomonic compositing onto the star plate.

The spatial app is equirect-only (every scene is a 2:1 stereo sphere), but the deep-sky
masters in _raw/deepsky/ are FLAT framed astrophotos (a galaxy fills a small slice of real
sky, not 360). Feeding one straight to the equirect pipeline would squash a square Carina to
2:1. So this adds a COMPOSE stage ahead of the existing depth->stereo->pack:

  1. compose  — project the flat master onto a tangent plane at a chosen sky position
                (center_lon/lat) and horizontal FOV, gnomonic (rectilinear) so straight
                structure doesn't bow, edge-feather it, and ADD it (in linear light) over
                the dimmed Deep Star Map equirect. Additive is physically right for emission
                on black: dark sky adds nothing so the real stars show through untouched, and
                there's no alpha matte to clip the faint galaxy halo. -> mono 2:1 equirect PNG.
  2. stereo    — the EXISTING deepspace recipe (synth_pack): near-uniform vergence
                (depth_floor 0.94, smooth 0.07, baseline 0.22%, cos^2 poles). Proven on device
                to fuse; keeps a whisper of relief. No V100/comfy dependency (luminance depth).
  3. pack      — pack_spatial.swift -> Backdrop/spatial_<name>.heic + Thumbnails/<name>.jpg.

Placement params below are first guesses (center-ahead, on the equator); expect to nudge
FOV / lon / feather / exposure on device. A depth-enhanced variant (DA V2 relief on the
pillars) is a possible follow-up A/B but needs the comfy/V100 path — deliberately NOT the
default here.

2026-07-24, third wrap round: the projection compose above is now the LEGACY path
(--legacy). Default is compose_sky360 — every scene becomes a FULL 360 sphere via
diffusion outpaint on the pod (sky360.py: outpaint -> seam close -> USDU refine),
then RealESRGAN x4 to target, pole soften, and the original high-res master
re-composited over its footprint. Rick: immersion and realistic feel supersede
accuracy; diffusion first for proportions, upscale second.

Run:  python3 upscale/deepsky_pipeline.py                 # all, resumable
      python3 upscale/deepsky_pipeline.py --only spatial_m16_pillars --force
      python3 upscale/deepsky_pipeline.py --preview spatial_m16_pillars  # mono only, no stereo
      python3 upscale/deepsky_pipeline.py --legacy ...    # old projection compose
"""
import argparse
import os
import sys
import tempfile
import time

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, "scripts"))
from backdrop_tool import open_rgb, tonemap                    # noqa: E402
from process_backdrops import synth_pack, BACKDROP, TARGET_W, TARGET_H  # noqa: E402

Image.MAX_IMAGE_PIXELS = None
DEEPSKY = os.path.join(REPO, "Float/Resources/Textures/_raw/deepsky")
STARMAP = os.path.join(REPO, "Float/Resources/Textures/_raw/starmap_2020_8k.exr")
BASE_DIM = 0.72            # star plate dim. 0.55 read as "floating in the dark" on device
MASTER_CAP = 12000        # effectively native for all masters (largest is 11472). The old
                          # 6000 cap + gnomonic edge stretch read as "pixelated" on device.
HALO_FOV_SCALE = 1.45     # glow underlayer spreads this far beyond the sharp frame
HALO_FOV_MAX = 165.0      # gnomonic blows up toward 180
HALO_GAIN = {"field": 0.30, "object": 0.18}

# name -> placement. kind: "field" (fills forward view) or "object" (discrete on black).
# fov_x_deg = horizontal angular width on the sphere; vertical follows the master's aspect.
# center_lon/lat in degrees (0,0 = straight ahead on the equator). feather = edge fade frac.
# exposure = stops applied to the final composite (Reinhard tonemap tames the bright cores).
# Device round 1 (Pillars + Sombrero): fields read as "a picture floating in the dark",
# objects "tiny". Fields: +~25% fov, wider feather, brighter plate + halo underlayer so the
# frame dissolves into glow. Objects: ~1.7x angular size. Fov stays gnomonic-safe (<=150 for
# sharp layers; edge stretch 1/cos^2 is ~15x at 150 but lives in the feathered fringe).
MANIFEST = [
    # ── nebula fields (fill the forward view) ────────────────────────────────
    # rot=1: vertically-composed masters turned 90deg CCW so the structure runs horizontally
    # (reads as a nebula bank, not a tall painting) — Rick's call, device round 1.
    ("spatial_carina_mystic",  "carina_hh901_mystic_mountain_heic1007c.tif", "field",  dict(fov_x=150, lon=0, lat=0, feather=0.30, exposure=0.3, rot=1)),
    ("spatial_m16_pillars",    "m16_pillars_visible_heic1501a.tif",          "field",  dict(fov_x=128, lon=0, lat=6, feather=0.30, exposure=0.4)),
    ("spatial_m8_lagoon",      "m8_lagoon_visible_8kx8k.png",                 "field",  dict(fov_x=144, lon=0, lat=0, feather=0.30, exposure=0.3, rot=1)),
    ("spatial_s106_angel",     "s106_snow_angel_heic1118a.tif",              "field",  dict(fov_x=118, lon=0, lat=0, feather=0.28, exposure=0.4)),
    # ── discrete objects on black (hero hanging in the void) ─────────────────
    ("spatial_m104_sombrero",  "m104_sombrero_opo0328a.tif",                 "object", dict(fov_x=78,  lon=0, lat=2, feather=0.12, exposure=0.2)),
    # A/B vs the approved gnomonic Sombrero: equidistant wrap + bigger, to judge immersion.
    ("spatial_m104_sombrero_wrap", "m104_sombrero_opo0328a.tif",             "object", dict(fov_x=95,  lon=0, lat=2, feather=0.12, exposure=0.2, proj="equidistant")),
    ("spatial_m106_spiral",    "m106_heic1302a_7910x6178.tif",               "object", dict(fov_x=70,  lon=0, lat=2, feather=0.12, exposure=0.2)),
    ("spatial_ngc4631_whale",  "ngc4631_whale_potw1146a.tif",                "object", dict(fov_x=92,  lon=0, lat=0, feather=0.14, exposure=0.2)),
    ("spatial_m31_andromeda",  "m31_andromeda_phat_10k_heic1502a.tif",       "object", dict(fov_x=118, lon=0, lat=0, feather=0.16, exposure=0.3)),
]

# Sky360 prompt descriptors for the hand rows (auto rows carry their POTM titles).
HAND_DESC = {
    "spatial_carina_mystic":  "the towering nebula mountains of the Carina Nebula",
    "spatial_m16_pillars":    "the Pillars of Creation in the Eagle Nebula",
    "spatial_m8_lagoon":      "the glowing clouds of the Lagoon Nebula",
    "spatial_s106_angel":     "the Snow Angel bipolar star-forming nebula",
    "spatial_m104_sombrero":  "the Sombrero Galaxy floating edge-on in the void",
    "spatial_m104_sombrero_wrap": "the Sombrero Galaxy floating edge-on in the void",
    "spatial_m106_spiral":    "the spiral galaxy M106",
    "spatial_ngc4631_whale":  "the edge-on Whale Galaxy",
    "spatial_m31_andromeda":  "the vast Andromeda Galaxy",
}

# Auto-generated POTM rows (see potm_auto_manifest.py) — same tuple shape, rel paths
# reach ../potm relative to DEEPSKY. Titles ride along as the sky360 prompt desc.
_AUTO = os.path.join(HERE, "deepsky_auto.json")
if os.path.exists(_AUTO):
    import json as _json
    with open(_AUTO) as _f:
        MANIFEST += [(r["name"], r["rel"], r["kind"],
                      dict(r["params"],
                           desc=r["params"].get("desc") or r.get("title", r["name"])))
                     for r in _json.load(_f)]


def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def _srgb_to_linear(u8):
    s = u8.astype(np.float32) / 255.0
    return np.where(s <= 0.04045, s / 12.92, ((s + 0.055) / 1.055) ** 2.4)


def load_base_linear(w, h):
    """Deep Star Map plate as linear RGB at (w,h), dimmed. EXR routed through sips (the
    Radiance RGBE parser can't read OpenEXR — same reason process_backdrops uses sips)."""
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tf:
        tmp = tf.name
    try:
        import subprocess
        subprocess.run(["sips", "-s", "format", "png", STARMAP, "--out", tmp],
                       check=True, capture_output=True)
        im = Image.open(tmp).convert("RGB").resize((w, h), Image.LANCZOS)
    finally:
        os.unlink(tmp)
    return _srgb_to_linear(np.asarray(im, np.uint8)) * BASE_DIM


def load_master_linear(rel, rot=0):
    """Master as linear RGB, long side capped at MASTER_CAP. `rot` = CCW quarter-turns —
    these masters are all ~square or landscape, so rotation reorients vertically-composed
    CONTENT (e.g. a towering pillar becomes a horizontal nebula bank); it doesn't change
    the wrapped footprint of a square frame."""
    im = open_rgb(os.path.join(DEEPSKY, rel))
    sw, sh = im.size
    scale = MASTER_CAP / max(sw, sh)
    if scale < 1.0:
        im = im.resize((max(1, round(sw * scale)), max(1, round(sh * scale))), Image.LANCZOS)
    arr = _srgb_to_linear(np.asarray(im.convert("RGB"), np.uint8))
    if rot:
        arr = np.rot90(arr, k=rot).copy()
    return arr


def _smoothstep(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _bilinear(src, u, v):
    """Bilinear sample src[H,W,3] at float coords (u=x, v=y); out-of-range -> 0."""
    H, W = src.shape[:2]
    x0 = np.floor(u).astype(np.int64); y0 = np.floor(v).astype(np.int64)
    x1 = x0 + 1; y1 = y0 + 1
    fx = (u - x0)[..., None]; fy = (v - y0)[..., None]
    def g(xx, yy):
        ok = (xx >= 0) & (xx < W) & (yy >= 0) & (yy < H)
        xc = np.clip(xx, 0, W - 1); yc = np.clip(yy, 0, H - 1)
        return src[yc, xc] * ok[..., None]
    top = g(x0, y0) * (1 - fx) + g(x1, y0) * fx
    bot = g(x0, y1) * (1 - fx) + g(x1, y1) * fx
    return top * (1 - fy) + bot * fy


def _add_layer(base, master, lon0_deg, lat0_deg, fov_x_deg, feather, gain=1.0, lum_key=False,
               proj="gnomonic"):
    """Project `master` onto the equirect `base` (linear light, additive).

    proj="gnomonic": tangent plane — straight structure stays straight, but off-axis it IS
    a flat plane ("extends out flat" on device) and edge scale blows up 1/cos^2 (15x at a
    150-deg field's edge — the "pixelated" report). Kept for narrow objects (approved look).
    proj="equidistant": azimuthal equidistant — uniform angular scale wraps the image around
    the viewer, so wide fields curve like a surrounding cloud bank and keep pixel density to
    the edge. Nebulae have no straight lines, so the bowing gnomonic avoids is invisible.
    """
    h, w = base.shape[:2]
    sh, sw = master.shape[:2]

    lon0 = np.radians(lon0_deg); lat0 = np.radians(lat0_deg)
    halfx_ang = np.radians(fov_x_deg) / 2.0          # angular half-width, both projections
    if proj == "gnomonic":
        xmax = np.tan(halfx_ang)                     # tangent-plane half-width
    else:
        xmax = halfx_ang                             # plane coords ARE angles
    ymax = xmax * (sh / sw)                          # square pixels -> half-height by aspect

    # Restrict work to the equirect window the object can touch (+ margin for feather/curve).
    half_lon = halfx_ang * 1.15 + np.radians(4)
    half_lat = halfx_ang * (sh / sw) * 1.15 + np.radians(4)
    c_col = int((lon0 / (2 * np.pi) + 0.5) * w)
    c_row = int((0.5 - lat0 / np.pi) * h)
    dcol = min(int(np.ceil(half_lon / (2 * np.pi) * w)), w // 2)
    drow = int(np.ceil(half_lat / np.pi * h))
    r0, r1 = max(0, c_row - drow), min(h, c_row + drow)
    cols = np.mod(np.arange(c_col - dcol, c_col + dcol), w)     # wrap-safe column indices

    lon = (cols / w - 0.5) * 2 * np.pi                          # [-pi, pi)
    lat = (0.5 - np.arange(r0, r1) / h) * np.pi                 # +pi/2 .. -pi/2
    LON, LAT = np.meshgrid(lon, lat)
    dlon = LON - lon0

    cosc = np.sin(lat0) * np.sin(LAT) + np.cos(lat0) * np.cos(LAT) * np.cos(dlon)
    if proj == "gnomonic":
        front = cosc > 1e-6
        denom = np.where(front, cosc, 1.0)
    else:
        # k = c/sin(c) rescales the sine-based direction components to arc length.
        c = np.arccos(np.clip(cosc, -1.0, 1.0))
        front = c < np.radians(160)                  # keep well clear of the antipode pole
        sinc = np.sin(c)
        denom = np.where(sinc > 1e-6, sinc / np.where(c > 1e-6, c, 1.0), 1.0)
    Xt = np.cos(LAT) * np.sin(dlon) / denom
    Yt = (np.cos(lat0) * np.sin(LAT) - np.sin(lat0) * np.cos(LAT) * np.cos(dlon)) / denom

    inside = front & (np.abs(Xt) <= xmax) & (np.abs(Yt) <= ymax)
    u = (Xt / xmax * 0.5 + 0.5) * (sw - 1)
    v = (0.5 - Yt / ymax * 0.5) * (sh - 1)                      # +Yt = up = row 0
    samp = _bilinear(master, u, v)

    fx = _smoothstep((xmax - np.abs(Xt)) / (feather * xmax + 1e-9))
    fy = _smoothstep((ymax - np.abs(Yt)) / (feather * ymax + 1e-9))
    alpha = np.where(inside, np.minimum(fx, fy), 0.0)

    if lum_key:
        # Discrete objects sit on (near-)black, but the master's background isn't pure zero,
        # so the feathered frame reads as a faint rectangular panel. Key on the sampled
        # luminance so only the object's own emission contributes and the frame dissolves into
        # the real stars. Gentle knee preserves the faint galaxy halo. NOT applied to fields —
        # there a luminance key would punch holes in the dark dust lanes that ARE the structure.
        Lm = 0.2126 * samp[..., 0] + 0.7152 * samp[..., 1] + 0.0722 * samp[..., 2]
        alpha = alpha * _smoothstep((Lm - 0.003) / (0.030 - 0.003))

    base[r0:r1, cols] += samp * alpha[..., None] * gain


def _linear_to_srgb_u8(lin):
    s = np.where(lin <= 0.0031308, lin * 12.92, 1.055 * np.clip(lin, 0, 1) ** (1 / 2.4) - 0.055)
    return (np.clip(s, 0, 1) * 255 + 0.5).astype(np.uint8)


def _blur_master(master, long_side=96, up=512):
    """Structureless glow copy of the master: crush to ~96px, gaussian, back up to ~512.
    In/out are linear light; the PIL round-trip is done in sRGB encoding."""
    from PIL import ImageFilter
    im = Image.fromarray(_linear_to_srgb_u8(master), "RGB")
    sw, sh = im.size
    scale = long_side / max(sw, sh)
    small = im.resize((max(1, round(sw * scale)), max(1, round(sh * scale))), Image.LANCZOS)
    small = small.filter(ImageFilter.GaussianBlur(radius=6))
    scale = up / max(small.size)
    big = small.resize((round(small.size[0] * scale), round(small.size[1] * scale)),
                       Image.BILINEAR)
    return _srgb_to_linear(np.asarray(big, np.uint8))


def compose(rel, kind, p, out_png, w=TARGET_W, h=TARGET_H):
    """Star plate + wide blurred glow underlayer + sharp gnomonic master, in linear light.

    The halo underlayer (device round-1 fix) spreads the master's own colors well past the
    sharp frame at low gain, so the image dissolves into ambient glow instead of ending at a
    feathered rectangle floating in darkness.
    """
    base = load_base_linear(w, h)
    master = load_master_linear(rel, rot=p.get("rot", 0))

    proj = p.get("proj") or ("equidistant" if kind == "field" else "gnomonic")
    # HALO_FOV_MAX guards gnomonic blow-up only; equidistant wraps safely much wider,
    # and pano fields (fov >= ~150) need the halo to spread PAST the sharp layer.
    halo_fov = min(p["fov_x"] * HALO_FOV_SCALE,
                   HALO_FOV_MAX if proj == "gnomonic" else 300.0)
    _add_layer(base, _blur_master(master), p["lon"], p["lat"], halo_fov,
               feather=0.55, gain=HALO_GAIN[kind], proj=proj)
    _add_layer(base, master, p["lon"], p["lat"], p["fov_x"], p["feather"],
               lum_key=(kind == "object"), proj=proj)

    mono = tonemap(base, exposure=p["exposure"])
    Image.fromarray(mono, "RGB").save(out_png)
    return (w, h)


SKY_CACHE = os.path.join(REPO, "Float/Resources/Textures/_raw/_sky_cache")

# Samples across the footprint for the _paste_master frequency split. Only has to be
# fine enough to follow a TONE STEP between the master and the surround (a whole-rect
# gradient); anything finer starts transplanting the sky's blurred structure over the
# master's real detail. 12 is ~1/12 of the footprint in each axis.
LOWPASS_SAMPLES = 12


def _wrap_hsmear(strip, nw):
    """Horizontally band-limit a row strip to `nw` samples, circularly. Float throughout
    (an 8-bit round trip on the smoothest content in the frame, at the zenith, is exactly
    where contour rings show) and wrap-padded (a clamped resample leaves a hairline at
    lon 180 straight overhead)."""
    hh, w = strip.shape[:2]
    if nw >= w:
        return strip
    pad = max(8, w // 64)
    padded = np.concatenate([strip[:, -pad:], strip, strip[:, :pad]], axis=1)
    pw = max(1, round(nw * (w + 2 * pad) / w))
    out = np.empty_like(strip)
    for c in range(3):
        ch = Image.fromarray(np.ascontiguousarray(padded[..., c], np.float32), "F")
        sm = ch.resize((pw, hh), Image.LANCZOS).resize((w + 2 * pad, hh), Image.BILINEAR)
        out[..., c] = np.asarray(sm, np.float32)[:, pad:pad + w]
    return out


def pole_soften(lin, start_deg=60.0, steps=48):
    """Kill the zenith/nadir whirlpool by band-limiting azimuthally as 1/cos(lat).

    Equirect maps every pixel of the top row onto ONE point. Any azimuthal variation
    left up there is therefore wound around that point, which is what reads as a
    whirlpool/pinwheel overhead — and diffusion generates the frame with no idea the
    projection does this. The previous fix smeared the pole band to a fixed w/16, which
    still leaves ~768 distinct values on the top row: a coarser whirlpool, not no
    whirlpool.

    The projection itself says what the answer is. At latitude `lat` the azimuthal scale
    is compressed by cos(lat), so holding ANGULAR resolution constant means low-passing
    horizontally to w*cos(lat) samples. That goes to 1 at the pole, i.e. the top row
    degenerates to its own mean and there is nothing left to spin. Easing the exponent in
    from `start_deg` keeps the useful mid-latitude band at full resolution — applying the
    law from the equator would be defensible but would visibly soften the horizon.
    """
    h, w = lin.shape[:2]
    lat = np.abs((0.5 - (np.arange(h) + 0.5) / h) * 180.0)
    ramp = _smoothstep((lat - start_deg) / (90.0 - start_deg))
    cos = np.clip(np.cos(np.radians(lat)), 1e-9, 1.0)
    target = np.clip(w * cos ** ramp, 1.0, w)              # samples this row may carry
    # Quantise onto a geometric ladder so each pole costs ~`steps` strip resamples
    # rather than one per row.
    ladder = np.unique(np.round(np.geomspace(1, w, steps)).astype(np.int64))
    idx = np.searchsorted(ladder, target)                  # first ladder >= target
    idx = np.clip(idx, 0, len(ladder) - 1)
    out = lin.copy()
    for j in np.unique(idx):
        nw = int(ladder[j])
        if nw >= w:
            continue
        rows = np.flatnonzero(idx == j)
        # `lat` is symmetric about the equator, so each level matches a run near the TOP
        # and another near the BOTTOM. Taking rows[0]..rows[-1] as one span would smear
        # everything in between, i.e. the whole frame.
        for run in np.split(rows, np.flatnonzero(np.diff(rows) != 1) + 1):
            out[run[0]:run[-1] + 1] = _wrap_hsmear(lin[run[0]:run[-1] + 1], nw)
    return out


def _paste_master(base, master_lin, fov_x, lat, feather):
    """Re-composite the original high-res master (linear) over its footprint on the
    SR'd sky, feather-edged lerp — real detail survives the round-trip through the
    1536px diffusion canvas; the surround stays hallucinated."""
    h, w = base.shape[:2]
    sh, sw = master_lin.shape[:2]
    wf = int(round(w * fov_x / 360.0))
    hf = min(int(round(wf * sh / sw)), h)
    x0 = (w - wf) // 2
    y0 = max(0, min(h - hf, int(round(h * (0.5 - lat / 180.0) - hf / 2))))
    if wf > sw * 1.25:
        log(f"  WARN: master upscaled x{wf / sw:.2f} into its footprint "
            f"(neural-SR candidate — run master_sr.py)")
    im = Image.fromarray(_linear_to_srgb_u8(master_lin), "RGB").resize((wf, hf), Image.LANCZOS)
    m = _srgb_to_linear(np.asarray(im, np.uint8))

    def _lowpass(a):
        # cheap large-radius low-pass: downscale to LOWPASS_SAMPLES across the footprint,
        # back up. Float ('F') per channel — an 8-bit round-trip would posterize
        # linear-space darks.
        #
        # The sample COUNT is fixed, not the pixel size. It used to downscale to a fixed
        # 128 px wide, which is scale-dependent: across a 261deg pano footprint that is a
        # ~70 px cutoff (genuinely low-frequency), but across an 85deg object footprint it
        # is ~23 px — high enough to carry real structure. So on object scenes the split
        # was subtracting the MASTER's galaxies and adding back the SKY's, and the sky's
        # copy of them is the 1536 canvas blown up x8: fat blobs with ESRGAN ring halos.
        # That is the "galaxy clusters upscale as blobs" report — the pipeline was
        # substituting its own blurred rendering for the sharp originals it had just
        # pasted, on exactly the scenes with lots of small background objects.
        h2, w2 = a.shape[:2]
        lo_w = min(LOWPASS_SAMPLES, w2)
        lo_h = max(1, round(lo_w * h2 / w2))
        out = np.empty((h2, w2, 3), np.float32)
        for c in range(3):
            ch = Image.fromarray(np.ascontiguousarray(a[..., c], np.float32), "F")
            out[..., c] = np.asarray(ch.resize((lo_w, lo_h), Image.LANCZOS)
                                     .resize((w2, h2), Image.BILINEAR), np.float32)
        return out

    # Frequency-split composite (pilot round 2: a soft alpha alone still shows the
    # rectangle as a low-frequency tone step — the VAE/USDU round-trip shifts the
    # surround's tone relative to the original master). Force the master's low-pass
    # field to equal the sky's under its footprint; only real high-frequency detail
    # is added, so no tone boundary can survive.
    sky_rect = base[y0:y0 + hf, x0:x0 + wf]
    m = np.clip(m + _lowpass(sky_rect) - _lowpass(m), 0.0, None)
    fx = _smoothstep(np.minimum(np.arange(wf), np.arange(wf)[::-1]) / (feather * wf + 1e-9))
    fy = _smoothstep(np.minimum(np.arange(hf), np.arange(hf)[::-1]) / (feather * hf + 1e-9))
    a = np.minimum(fx[None, :], fy[:, None])[..., None]
    base[y0:y0 + hf, x0:x0 + wf] = sky_rect * (1 - a) + m * a


def compose_sky360(name, rel, kind, p, out_png, w=TARGET_W, h=TARGET_H):
    """Full-360 scene: diffusion sky (sky360.py) -> ESRGAN x4 to target -> pole
    soften -> original master re-composited. Mono equirect out, ready for synth_pack."""
    from sky360 import make_sky, SKY_RECIPE
    from neural_sr import sr_equirect
    master_lin = load_master_linear(rel, rot=p.get("rot", 0))
    master_u8 = Image.fromarray(_linear_to_srgb_u8(master_lin), "RGB")
    desc = p.get("desc") or HAND_DESC.get(name, "a deep space nebula")
    from sky360 import FOOT_FEATHER
    refined = make_sky(name, master_u8, p["fov_x"], p.get("lat", 0), desc, SKY_CACHE,
                       kind=kind)
    sr_png = os.path.join(SKY_CACHE, f"{name}_{SKY_RECIPE}_sr{w}.png")
    if os.path.exists(sr_png):
        sky = Image.open(sr_png).convert("RGB")
        log("  SR: cached")
    else:
        sky = sr_equirect(Image.open(refined).convert("RGB"), f"{name}_sky", w)
        sky.save(sr_png)
    base = _srgb_to_linear(np.asarray(sky, np.uint8))
    base = pole_soften(base)
    # feather comes from sky360, NOT the manifest: the manifest's `feather` is a legacy
    # projection-compose knob, and this ramp has to match the one build_canvas used.
    _paste_master(base, master_lin, p["fov_x"], p.get("lat", 0), FOOT_FEATHER[kind])
    mono = tonemap(base, exposure=p["exposure"])
    Image.fromarray(mono, "RGB").save(out_png)


def process(name, rel, kind, p, force, preview, legacy=False):
    out = os.path.join(BACKDROP, f"{name}.heic")
    if os.path.exists(out) and not force and not preview:
        log(f"skip {name} (exists)")
        return
    log(f"=== {name} ({kind}{'' if legacy else ', sky360'}) ===")
    with tempfile.TemporaryDirectory() as td:
        mono = os.path.join(td, "mono.png")
        if legacy:
            compose(rel, kind, p, mono)
            log(f"  composed {TARGET_W}x{TARGET_H} equirect (fov {p['fov_x']}deg, feather {p['feather']})")
        else:
            compose_sky360(name, rel, kind, p, mono)
            log(f"  sky360 {TARGET_W}x{TARGET_H} full-360 equirect (master at fov {p['fov_x']}deg)")
        if preview:
            suffix = "_rot" if p.get("rot") else ""
            dst = os.path.join(HERE, "deepsky_prev", f"{name}_mono{suffix}.jpg")
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            im = Image.open(mono).convert("RGB"); im.thumbnail((2048, 1024), Image.LANCZOS)
            im.save(dst, quality=90)
            log(f"  preview -> {dst}")
            return
        synth_pack(mono, None, name, "deepspace")
    mb = os.path.getsize(out) / 1e6
    log(f"  -> {name}.heic ({mb:.1f} MB) + thumbnail")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", help="one scene name")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--preview", nargs="?", const="__all__",
                    help="compose the mono equirect only (fast, no stereo/pack); "
                         "optionally name one scene")
    ap.add_argument("--rot90", action="store_true",
                    help="rotate the master 90deg CCW before wrapping (A/B experiment; "
                         "previews get a _rot filename suffix)")
    ap.add_argument("--legacy", action="store_true",
                    help="old projection compose (star plate + gnomonic/equidistant) "
                         "instead of the sky360 diffusion path")
    args = ap.parse_args()
    only = args.only or (args.preview if args.preview and args.preview != "__all__" else None)
    rows = [r for r in MANIFEST if not only or r[0] == only]
    preview = bool(args.preview)
    log(f"deep-sky: {len(rows)} scene(s){' (preview mono only)' if preview else ''}")
    ok = fail = 0
    for name, rel, kind, p in rows:
        try:
            if args.rot90:
                p = dict(p, rot=1)
            process(name, rel, kind, p, args.force, preview, legacy=args.legacy)
            ok += 1
        except Exception as e:                                   # noqa: BLE001
            fail += 1
            import traceback; traceback.print_exc()
            log(f"  !! FAILED {name}: {e}")
    log(f"DONE: {ok} ok, {fail} failed")
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
