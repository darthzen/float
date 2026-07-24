#!/usr/bin/env python3
"""Compose N all-sky band maps (FITS strips from fetch_unwise.py) into an RGB equirect.

Source-agnostic "band maps -> RGB" stage: the unWISE W1/W2 recipe is one named
config; the SPHEREx Year-1 102-band cubes drop in later as another (different
matrix/scales, same code path). Colorization is the Lang/Legacy-Surveys
convention (legacypipe _unwise_to_rgb): color-preserving asinh — luminance is
stretched, per-band ratios are kept, which is what tames the galactic bulge
without greying its color.

  python3 upscale/allsky_rgb.py --preview                 # 4096 preview -> deepsky_prev/
  python3 upscale/allsky_rgb.py --preview --simulate-tonemap   # post-Reinhard look
  python3 upscale/allsky_rgb.py                           # full res -> _raw/unwise/*.tif

FITS is hand-parsed (single primary HDU, BITPIX -32/-64) — the pipeline env has
only numpy+PIL, and astropy for two keywords is not worth the dependency
(precedent: backdrop_tool.py hand-parses Radiance RGBE).
"""
import argparse
import os
import sys
import time

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(REPO, "scripts"))
from backdrop_tool import tonemap                                    # noqa: E402

Image.MAX_IMAGE_PIXELS = None
FITS_DIR = os.path.join(REPO, "Float/Resources/Textures/_raw/unwise/fits")
OUT_TIF = os.path.join(REPO, "Float/Resources/Textures/_raw/unwise/unwise_w1w2_equirectangular.tif")
PREV_DIR = os.path.join(HERE, "deepsky_prev")

# band order matches the row order of `matrix` columns; matrix rows are R, G, B.
UNWISE = dict(
    bands=["W1", "W2"],
    scales=[50.0, 50.0],
    matrix=[[0.0, 1.0],   # R = W2 (4.6um — dust)
            [0.5, 0.5],   # G = synthetic mean
            [1.0, 0.0]],  # B = W1 (3.4um — stars)
    mn=-1.0, mx=100.0, arcsinh=1.0,
)


def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def read_fits(path):
    """Primary HDU of a hips2fits render -> float32 array (FITS row 0 = bottom)."""
    with open(path, "rb") as f:
        raw = f.read()
    hdr = {}
    end = 0
    for blk in range(0, len(raw), 2880):
        for i in range(blk, blk + 2880, 80):
            card = raw[i:i + 80].decode("ascii", "replace")
            key = card[:8].strip()
            if key == "END":
                end = blk + 2880
                break
            if "=" in card:
                hdr[key] = card.split("=", 1)[1].split("/")[0].strip()
        if end:
            break
    w, h, bitpix = int(hdr["NAXIS1"]), int(hdr["NAXIS2"]), int(hdr["BITPIX"])
    dt = {-32: ">f4", -64: ">f8"}[bitpix]
    n = w * h * abs(bitpix) // 8
    return np.frombuffer(raw[end:end + n], dtype=dt).reshape(h, w).astype(np.float32)


def load_band(band, preview):
    """Assemble one band: single preview file, or bottom-up full-res strips."""
    if preview:
        return read_fits(os.path.join(FITS_DIR, f"{band}_preview.fits"))
    strips = sorted(p for p in os.listdir(FITS_DIR)
                    if p.startswith(f"{band}_strip") and p.endswith(".fits"))
    if not strips:
        raise FileNotFoundError(f"no {band}_strip*.fits in {FITS_DIR} — run fetch_unwise.py fetch")
    return np.vstack([read_fits(os.path.join(FITS_DIR, s)) for s in strips])


def compose(bands, matrix, scales, mn, mx, arcsinh, bg_pct=None):
    """Lang color-preserving asinh: stretch the band mean, keep per-band ratios,
    then mix channels via `matrix` and normalize to the (mn, mx) cuts."""
    imgs = []
    for a, s in zip(bands, scales):
        a = np.nan_to_num(a, nan=0.0, posinf=0.0, neginf=0.0)
        if bg_pct is not None:
            a = np.clip(a - np.percentile(a, bg_pct), 0.0, None)
        imgs.append(a / s)
    mean = np.mean(imgs, axis=0)
    nlmap = lambda x: np.arcsinh(x * arcsinh) / np.sqrt(arcsinh)   # noqa: E731
    with np.errstate(divide="ignore", invalid="ignore"):
        gain = np.where(mean != 0, nlmap(mean) / mean, 0.0)
    lo, hi = nlmap(mn), nlmap(mx)
    stretched = [(im * gain - lo) / (hi - lo) for im in imgs]
    rgb = np.clip(np.tensordot(np.asarray(matrix), np.asarray(stretched), axes=1), 0.0, 1.0)
    rgb = np.moveaxis(rgb, 0, -1)
    # TPDF dither before the 8-bit quantize: the diffuse glow is a smooth latitude
    # gradient, so bare quantization contours it into horizontal bands (~one step
    # per 2 deg of sky at these cuts) that HEIC compression then accentuates. One
    # shared noise plane for all channels — luminance dither without color speckle.
    # Seeded: the compose stays reproducible run-to-run.
    rng = np.random.default_rng(20260724)
    tri = rng.random(rgb.shape[:2], dtype=np.float32) + rng.random(rgb.shape[:2], dtype=np.float32) - 1.0
    return np.clip(rgb * 255.0 + tri[..., None] + 0.5, 0.0, 255.0).astype(np.uint8)


def seam_check(rgb):
    # A star field makes ANY adjacent column pair differ, so judge the wrap seam
    # against the interior adjacent-column level rather than an absolute number.
    a = rgb.astype(np.int16)
    seam = float(np.abs(a[:, 0] - a[:, -1]).mean())
    w = rgb.shape[1]
    interior = float(np.mean([np.abs(a[:, c] - a[:, c + 1]).mean()
                              for c in (w // 8, w // 3, 2 * w // 3, 7 * w // 8)]))
    log(f"  wrap seam diff {seam:.2f} vs interior baseline {interior:.2f}")
    if seam > 2.0 * interior:
        log("  !! seam well above interior baseline — check strip WCS before shipping")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", action="store_true", help="use *_preview.fits, JPG only")
    ap.add_argument("--bg-pct", type=float, default=None,
                    help="per-band percentile background subtraction (e.g. 30)")
    ap.add_argument("--auto-cut", action="store_true",
                    help="derive mn/mx from data percentiles (if flux units are off)")
    ap.add_argument("--mn", type=float, default=None, help="override low cut (Lang default -1)")
    ap.add_argument("--mx", type=float, default=None, help="override high cut (Lang default 100)")
    ap.add_argument("--simulate-tonemap", action="store_true",
                    help="preview through the pipeline's Reinhard tonemap")
    ap.add_argument("--exposure", type=float, default=0.0, help="stops, with --simulate-tonemap")
    args = ap.parse_args()

    cfg = dict(UNWISE)
    band_names = cfg.pop("bands")
    if args.mn is not None:
        cfg["mn"] = args.mn
    if args.mx is not None:
        cfg["mx"] = args.mx
    bands = []
    for b in band_names:
        a = load_band(b, args.preview)
        log(f"  {b}: {a.shape[1]}x{a.shape[0]}, median {np.nanmedian(a):.1f}")
        bands.append(a)
    if args.auto_cut:
        ref = np.nan_to_num(np.mean(bands, axis=0))
        cfg["mn"], cfg["mx"] = np.percentile(ref, 1) / cfg["scales"][0], np.percentile(ref, 99.9) / cfg["scales"][0]
        log(f"  auto cuts: mn={cfg['mn']:.2f} mx={cfg['mx']:.2f}")

    rgb = compose(bands, bg_pct=args.bg_pct, **cfg)
    rgb = rgb[::-1]                      # FITS bottom-up -> image top-down
    seam_check(rgb)

    if args.simulate_tonemap:
        srgb = rgb.astype(np.float32) / 255.0
        lin = np.where(srgb <= 0.04045, srgb / 12.92, ((srgb + 0.055) / 1.055) ** 2.4)
        rgb = tonemap(lin, exposure=args.exposure)

    os.makedirs(PREV_DIR, exist_ok=True)
    im = Image.fromarray(rgb, "RGB")
    prev = im if im.width <= 2048 else im.resize((2048, 1024), Image.LANCZOS)
    tag = "_tonemap" if args.simulate_tonemap else ""
    if args.bg_pct is not None or args.mn is not None or args.mx is not None:
        tag += f"_bg{args.bg_pct or 0:g}_mn{cfg['mn']:g}_mx{cfg['mx']:g}"
    jpg = os.path.join(PREV_DIR, f"unwise_w1w2{tag}.jpg")
    prev.save(jpg, quality=90)
    log(f"  preview -> {jpg}")

    if not args.preview:
        os.makedirs(os.path.dirname(OUT_TIF), exist_ok=True)
        im.save(OUT_TIF, compression="tiff_adobe_deflate")
        log(f"  full res -> {OUT_TIF} ({os.path.getsize(OUT_TIF)/1e6:.0f} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
