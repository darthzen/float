#!/usr/bin/env python3
"""Mono equirectangular -> stereo (L/R) equirectangular via depth-image-based rendering.

Stage 2 of the spatial pipeline. Consumes a mono 2:1 equirect + a depth map and
emits two equirects (left/right eye) that `pack_spatial.swift` wraps into the
2-image HEIC the app reads (SpatialImageEnvironment: CGImage 0 = left, 1 = right).

Edge handling (added after the 1.0% headset test flagged mountain/sky dissonance
on Rogland): DA V2's depth silhouette is soft (inference at ~518px) while the
color silhouette is sharp, so a guided filter snaps the depth edge onto the color
edge, and a forward warp (foreground-priority scatter + background hole-fill)
replaces the old inverse warp so silhouettes shift cleanly instead of smearing.

Geometry — omnidirectional stereo (ODS) baked into the texture:
  * depth d in [0,1], near=1 far=0 (so bright nebula / near ground push forward).
  * per-pixel horizontal disparity  D(x,y) = baseline_px * d * cos(latitude).
    The cos(lat) term is REQUIRED for equirect: a horizontal pixel step spans
    less world-angle near the poles, and horizontal parallax is meaningless at
    the pole itself, so disparity must fall to 0 there or the zenith/nadir smear.
  * left eye samples the source shifted +D/2, right eye -D/2 (inverse warp).
  * residual disocclusion holes (where depth steps sharply) are filled by
    horizontal edge-stretch — invisible on a backdrop, and cheap.

Baseline is the comfort knob (§9). The Apple-Spatial reference files carry
~0.8% of width; default here is a deliberately gentler 0.6%.

  python3 stereo_synth.py --depth d.png --baseline-frac 0.006 mono.heic outdir/
outputs outdir/<stem>_left.png and _right.png.
"""

import argparse
import os
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

Image.MAX_IMAGE_PIXELS = None


def open_rgb(path):
    """RGB loader that routes HEIC through sips (PIL can't decode HEIC)."""
    if path.lower().endswith((".heic", ".heif")):
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tf:
            tmp = tf.name
        try:
            subprocess.run(["sips", "-s", "format", "png", path, "--out", tmp],
                           check=True, capture_output=True)
            return Image.open(tmp).convert("RGB").copy()
        finally:
            os.unlink(tmp)
    return Image.open(path).convert("RGB")


def load_depth(path, size):
    """Depth as float32 in [0,1], near=1. Resized to (W,H). Accepts HEIC/PNG/…"""
    im = open_rgb(path).convert("L").resize(size, Image.LANCZOS)
    d = np.asarray(im, dtype=np.float32) / 255.0
    lo, hi = float(d.min()), float(d.max())
    return (d - lo) / (hi - lo) if hi > lo else d


def luminance_depth(rgb):
    """Fallback pseudo-depth for DEEP-SPACE skies: brightness = nearness.

    Correct only where luminous = close (nebula/stars in front of void). WRONG
    for grounded skies (bright sky is far) — those must use a real depth map.
    """
    a = rgb.astype(np.float32) / 255.0
    L = 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]
    # gentle gamma so only genuinely bright structure gains disparity
    return np.clip(L, 0, 1) ** 1.5


def _box(x, r):
    """Separable box blur (radius r) via cumulative sums, edge-clamped."""
    def blur1d(a, axis):
        n = a.shape[axis]
        c = np.cumsum(a, axis=axis)
        c = np.concatenate([np.zeros_like(np.take(c, [0], axis=axis)), c], axis=axis)
        lo = np.clip(np.arange(n) - r, 0, n)
        hi = np.clip(np.arange(n) + r + 1, 0, n)
        idx = [slice(None)] * a.ndim
        idx_hi = list(idx); idx_hi[axis] = hi
        idx_lo = list(idx); idx_lo[axis] = lo
        cnt = (hi - lo).astype(np.float32)
        shape = [1] * a.ndim; shape[axis] = n
        return (c[tuple(idx_hi)] - c[tuple(idx_lo)]) / cnt.reshape(shape)
    return blur1d(blur1d(x, 0), 1)


def guided_refine(depth, guide, r=12, eps=1e-3):
    """Guided filter: snap `depth` edges onto `guide` (color-luma) edges.

    DA V2's depth silhouette is soft (inference runs at ~518px, then upsamples),
    while the color silhouette is razor-sharp at full res. Warping sharp color by
    a soft-edged disparity smears the ridge into the sky — the exact "dissonance
    at the mountain/sky border" seen on Rogland at 1.0%. The guided filter makes
    the depth follow the color edge, so the disparity step lands on the silhouette.
    """
    I, p = guide.astype(np.float32), depth.astype(np.float32)
    mI, mp = _box(I, r), _box(p, r)
    varI = _box(I * I, r) - mI * mI
    covIp = _box(I * p, r) - mI * mp
    a = covIp / (varI + eps)
    b = mp - a * mI
    return np.clip(_box(a, r) * I + _box(b, r), 0.0, 1.0)


def forward_warp(src, disp_px):
    """Forward-warp: each SOURCE pixel scatters to x + disp, foreground wins.

    Replaces the earlier inverse warp. Inverse warp sampled disparity at the
    destination, which at a depth step drags background pixels along with the
    foreground (the edge smear). Forward warp moves each surface by its own
    disparity and lets the nearer surface (larger disp) overwrite the farther one
    via a z-priority scatter; the gap revealed behind a foreground edge
    (disocclusion) is filled from the background neighbour — which is what the
    other eye actually sees there. Result: crisp silhouettes, clean fills.
    """
    H, W = src.shape[:2]
    xdst = np.mod(np.round(np.arange(W)[None, :] + disp_px).astype(np.int64), W)
    rows = np.arange(H)[:, None]
    flat = (rows * W + xdst).ravel()

    out = np.zeros((H * W, 3), np.float32)
    filled = np.zeros(H * W, bool)
    order = np.argsort(disp_px.ravel(), kind="stable")   # ascending: near written last
    fo = flat[order]
    out[fo] = src.reshape(-1, 3)[order]
    filled[fo] = True

    out = out.reshape(H, W, 3)
    filled = filled.reshape(H, W)
    # Fill disocclusion holes by horizontal nearest-neighbour (background side).
    if not filled.all():
        for y in np.where(~filled.all(axis=1))[0]:
            row, fm = out[y], filled[y]
            idx = np.where(fm, np.arange(W), 0)
            np.maximum.accumulate(idx, out=idx)            # forward-fill index
            back = np.where(fm[::-1], np.arange(W), 0)
            np.maximum.accumulate(back, out=back)          # backward-fill index
            bfill = (W - 1 - back[::-1])
            src_idx = np.where(fm, np.arange(W), np.where(idx > 0, idx, bfill))
            out[y] = row[src_idx]
    return np.clip(out, 0, 255).astype(src.dtype)


def synth(mono_path, depth_path, out_dir, baseline_frac,
          smooth_frac=0.0, pole_power=2.0, depth_floor=0.0):
    rgb = np.asarray(open_rgb(mono_path), dtype=np.uint8)
    H, W = rgb.shape[:2]
    if abs(W / H - 2.0) > 0.02:
        print(f"warning: {os.path.basename(mono_path)} is {W}x{H}, not 2:1 equirect")

    if depth_path:
        depth = load_depth(depth_path, (W, H))
        # Snap the soft ML depth edge onto the sharp color silhouette.
        luma = luminance_depth(rgb) ** (1 / 1.5)   # plain luma [0,1] as edge guide
        depth = guided_refine(depth, luma)
    else:
        depth = luminance_depth(rgb)

    if smooth_frac > 0:
        # DEEP-SPACE fix: luminance depth is per-pixel, so every bright STAR gets its own
        # large disparity while the void beside it gets none — the two eyes end up shoved
        # apart star-by-star and won't fuse ("wildly different"). Stars are at infinity and
        # deserve ~no parallax. Blurring the depth to a smooth low-frequency field means a
        # whole region (stars + nebula together) shares one gentle depth, so the eyes stay
        # fusable and only the large nebula masses read as nearer.
        r = max(1, int(smooth_frac * W))
        depth = _box(_box(depth, r), r)            # two boxes ≈ Gaussian
        lo, hi = float(depth.min()), float(depth.max())
        if hi > lo:
            depth = (depth - lo) / (hi - lo)

    if depth_floor > 0:
        # DEEP-SPACE fix (the real one): the imported skies that read well shift the whole
        # starfield by a nearly UNIFORM amount (measured ~0.25% global) — so every star moves
        # together and fuses as one field at one depth. Per-feature luminance depth instead
        # gives each star its own disparity (void=0, star=max) → stars at inconsistent depths
        # → won't fuse ("wildly different"). Lifting depth onto a high floor makes it
        # near-uniform (a global vergence) with only a whisper of nebula relief on top.
        depth = depth_floor + (1.0 - depth_floor) * depth

    lat = (np.arange(H, dtype=np.float32) / H - 0.5) * np.pi   # +pi/2 .. -pi/2
    # POLE/ZENITH fix: omnidirectional stereo is only correct near the horizon; toward the
    # poles the baked horizontal disparity degenerates into convergence that reads as
    # "overhead is closer." cos(lat) alone falls off too slowly — raising it to a power
    # drives disparity to near-zero well before the zenith (cos^2 at 60° = 0.25), so looking
    # up goes gracefully mono instead of pinching in.
    weight = np.clip(np.cos(lat), 0, 1)[:, None] ** pole_power
    baseline_px = baseline_frac * W
    disp = baseline_px * depth * weight                       # >=0, per pixel

    left = forward_warp(rgb, +0.5 * disp)     # left eye sees scene shifted right
    right = forward_warp(rgb, -0.5 * disp)

    os.makedirs(out_dir, exist_ok=True)
    stem = os.path.splitext(os.path.basename(mono_path))[0]
    lp = os.path.join(out_dir, f"{stem}_left.png")
    rp = os.path.join(out_dir, f"{stem}_right.png")
    Image.fromarray(left).save(lp)
    Image.fromarray(right).save(rp)
    print(f"{stem}: {W}x{H}  baseline={baseline_px:.0f}px "
          f"({baseline_frac:.1%})  depth={'map' if depth_path else 'luminance'}")
    print(f"  {lp}\n  {rp}")
    return lp, rp


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mono")
    ap.add_argument("out_dir")
    ap.add_argument("--depth", help="depth map (near=bright); omit to use luminance")
    ap.add_argument("--baseline-frac", type=float, default=0.006,
                    help="max disparity as fraction of width (comfort knob, §9)")
    ap.add_argument("--smooth-frac", type=float, default=0.0,
                    help="blur depth by this fraction of width (deep-space: ~0.02)")
    ap.add_argument("--pole-power", type=float, default=2.0,
                    help="disparity falloff toward poles = cos(lat)^power (zenith comfort)")
    ap.add_argument("--depth-floor", type=float, default=0.0,
                    help="lift depth onto this floor for near-uniform vergence (deep-space: ~0.65)")
    args = ap.parse_args()
    synth(args.mono, args.depth, args.out_dir, args.baseline_frac,
          args.smooth_frac, args.pole_power, args.depth_floor)


if __name__ == "__main__":
    main()
