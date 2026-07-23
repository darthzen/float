#!/usr/bin/env python3
"""Backdrop asset tooling for Float's L1 far backdrop (§4).

Two jobs, both of which were previously done by hand and do not scale as the
panorama library grows:

  ingest   raw panorama (JPEG / Radiance .hdr / PNG / TIFF) -> 8192x4096 HEIC
           in Resources/Textures/Backdrop/, with an explicit tonemap for HDR
           sources so night skies stay night (sips' default curve lifts the
           ground until it reads as dusk).

  measure  report the numbers FarBackdrop needs per panorama:
             busyness  0 = near-black star field, 1 = nebula-filled sky.
                       Blurred-luminance mean + large-scale variation +
                       non-black coverage, matching the scale the original six
                       were tuned on (see CREDITS.md / DepthLayers.swift).
             nadir     fraction of the bottom of the frame that is pure black.
                       ESO pads partial-sphere panoramas out to a nominal 2:1
                       with black fill; anything above a few percent looks down
                       into a void with a hard circular edge. Reject those.
             ground    fraction of frame height below the brightness step, i.e.
                       how much of the sphere is ground.

                       ADVISORY ONLY — it looks for a brightness discontinuity,
                       so it misses panoramas whose horizon fades gradually
                       (ground_lasilla_airglow is grounded but reports 0.0%).
                       `nadir` is the reliable automated check; the `grounded`
                       flag in FarBackdrop.catalog is set by eye, not from this.

Usage:
    python3 scripts/backdrop_tool.py measure Float/Resources/Textures/Backdrop/*.heic
    python3 scripts/backdrop_tool.py ingest  --exposure -1.5 raw.hdr out_name
"""

import argparse
import os
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

Image.MAX_IMAGE_PIXELS = None

TARGET_W, TARGET_H = 8192, 4096
BACKDROP_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "Float", "Resources", "Textures", "Backdrop",
)


# ---------------------------------------------------------------- loading

def _load_radiance(path):
    """Read a Radiance RGBE .hdr into a float32 linear RGB array.

    Parsed here rather than via imageio, whose .hdr support needs an OpenCV
    backend we would otherwise not depend on. Handles the new-style
    per-component RLE scanlines that every modern writer emits, and falls back
    to flat RGBE for old-style files.
    """
    with open(path, "rb") as f:
        data = f.read()

    # Header: text lines terminated by a blank line, then the resolution line.
    pos = 0
    while True:
        eol = data.index(b"\n", pos)
        line = data[pos:eol]
        pos = eol + 1
        if line.strip() == b"":
            break
    eol = data.index(b"\n", pos)
    res = data[pos:eol].split()
    pos = eol + 1
    if len(res) != 4 or res[0] != b"-Y" or res[2] != b"+X":
        raise ValueError(f"unsupported Radiance resolution line: {res!r}")
    H, W = int(res[1]), int(res[3])

    buf = np.frombuffer(data, dtype=np.uint8, offset=pos)
    rgbe = np.empty((H, W, 4), dtype=np.uint8)
    p = 0
    for y in range(H):
        if (W >= 8 and W < 32768 and buf[p] == 2 and buf[p + 1] == 2
                and (int(buf[p + 2]) << 8 | int(buf[p + 3])) == W):
            p += 4                                        # new-style RLE
            for c in range(4):
                x = 0
                while x < W:
                    n = int(buf[p]); p += 1
                    if n > 128:                            # run
                        rgbe[y, x:x + n - 128, c] = buf[p]; p += 1
                        x += n - 128
                    else:                                  # literal
                        rgbe[y, x:x + n, c] = buf[p:p + n]; p += n
                        x += n
        else:                                              # old-style flat
            rgbe[y] = buf[p:p + W * 4].reshape(W, 4)
            p += W * 4

    e = rgbe[..., 3].astype(np.int32)
    scale = np.where(e == 0, 0.0, np.exp2(e - 136)).astype(np.float32)
    return rgbe[..., :3].astype(np.float32) * scale[..., None]


def open_rgb(path):
    """Open any supported still as a PIL RGB image.

    PIL has no HEIC decoder, and the bundled backdrops are all HEIC, so route
    those through macOS ImageIO (sips) via a temporary PNG.
    """
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


def load_linear(path):
    """Load any supported source as float32 linear RGB in roughly [0, inf)."""
    if path.lower().endswith((".hdr", ".exr")):
        return _load_radiance(path)
    im = open_rgb(path)
    srgb = np.asarray(im, dtype=np.float32) / 255.0
    # sRGB -> linear so the tonemap below operates in the same space for all inputs.
    return np.where(srgb <= 0.04045, srgb / 12.92, ((srgb + 0.055) / 1.055) ** 2.4)


# ---------------------------------------------------------------- tonemap

def tonemap(lin, exposure=0.0, gamma=1.0, black=0.0):
    """Exposure (stops) -> optional black lift/crush -> Reinhard -> sRGB encode.

    Reinhard rather than a hard clip: night panoramas carry a very bright Milky
    Way core and moon against a near-black ground, and clipping blows the core
    into a flat white blob that reads as a light leak on the inside of a sphere.
    """
    x = lin * (2.0 ** exposure)
    if black:
        x = np.clip(x - black, 0.0, None)
    x = x / (1.0 + x)                                  # Reinhard
    if gamma != 1.0:
        x = np.clip(x, 0.0, 1.0) ** gamma
    x = np.clip(x, 0.0, 1.0)
    srgb = np.where(x <= 0.0031308, x * 12.92, 1.055 * (x ** (1 / 2.4)) - 0.055)
    return (np.clip(srgb, 0, 1) * 255.0 + 0.5).astype(np.uint8)


# ---------------------------------------------------------------- measuring

def _luma(rgb_u8):
    a = rgb_u8.astype(np.float32) / 255.0
    return 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]


def measure(path):
    """Return (busyness, nadir_black_fraction, ground_fraction) for a panorama."""
    im = open_rgb(path)
    W, H = im.size

    # --- nadir black fill: full-width rows at the very bottom that are pure black.
    tall = np.asarray(im.resize((64, 512), Image.BOX), dtype=np.uint8)
    black_rows = 0
    for y in range(511, -1, -1):
        if tall[y].max() <= 6:
            black_rows += 1
        else:
            break
    nadir = black_rows / 512.0

    # --- busyness: work at a small size so this measures large-scale structure
    # (nebulosity, the Milky Way band) and not per-star noise.
    small = np.asarray(im.resize((256, 128), Image.LANCZOS), dtype=np.uint8)
    L = _luma(small)
    mean = float(L.mean())
    variation = float(L.std())
    coverage = float((L > 0.06).mean())          # fraction that isn't void
    # Coefficients are a least-squares fit against the six values already tuned by
    # hand in DepthLayers.busyness (deep_star_map .00, dual_nebula .80,
    # blue_filaments .89, teal_orange .65, dark_dust .28, pale_haze .93), so new
    # panoramas land on the same scale as the originals. Max residual 0.047.
    # Coverage fits at ~0 weight — brightness and large-scale variation carry it,
    # and an early hand-picked coverage term was what read dark skies 0.2 high.
    busyness = float(np.clip(
        4.0485 * mean + 2.3968 * variation + 0.0941 * coverage - 0.2660, 0, 1))

    # --- ground fraction: scan up from the bottom for the horizon, i.e. the row
    # where the row-mean brightness steps up into sky. Ground in these panoramas
    # is consistently darker and much flatter than the sky above it.
    rows = L.mean(axis=1)
    valid = rows[: int(len(rows) * (1 - nadir))] if nadir < 0.95 else rows
    ground = 0.0
    if len(valid) > 8:
        bottom_half = valid[len(valid) // 2:]
        if bottom_half.size:
            step = np.diff(bottom_half)
            k = int(np.argmax(step)) if step.size else 0
            # Only call it a horizon if the step is a real discontinuity.
            if step.size and step[k] > 0.5 * float(bottom_half.std() + 1e-6) and step[k] > 0.004:
                ground = (len(valid) - (len(valid) // 2 + k)) / float(len(rows))
    return busyness, nadir, ground


# ---------------------------------------------------------------- commands

def cmd_measure(args):
    print(f"{'file':<34}{'busyness':>10}{'nadir':>9}{'ground':>9}   note")
    for p in args.paths:
        try:
            b, n, g = measure(p)
        except Exception as e:                                    # noqa: BLE001
            print(f"{os.path.basename(p):<34}  !! {e}")
            continue
        note = []
        if n > 0.03:
            note.append(f"REJECT black nadir {n:.0%}")
        if g > 0.05:
            note.append(f"grounded (~{g:.0%} ground)")
        print(f"{os.path.basename(p):<34}{b:>10.2f}{n:>9.1%}{g:>9.1%}   {', '.join(note)}")


def cmd_ingest(args):
    lin = load_linear(args.src)
    rgb = tonemap(lin, exposure=args.exposure, gamma=args.gamma, black=args.black)
    im = Image.fromarray(rgb, "RGB")
    if im.size != (TARGET_W, TARGET_H):
        im = im.resize((TARGET_W, TARGET_H), Image.LANCZOS)

    os.makedirs(BACKDROP_DIR, exist_ok=True)
    out = os.path.join(BACKDROP_DIR, args.name + ".heic")
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tf:
        tmp = tf.name
    try:
        im.save(tmp)
        subprocess.run(
            ["sips", "-s", "format", "heic", "-s", "formatOptions", str(args.quality),
             tmp, "--out", out],
            check=True, capture_output=True,
        )
    finally:
        os.unlink(tmp)

    b, n, g = measure(out)
    size_mb = os.path.getsize(out) / 1e6
    print(f"{args.name}.heic  {TARGET_W}x{TARGET_H}  {size_mb:.1f} MB   "
          f"busyness={b:.2f} nadir={n:.1%} ground={g:.1%}")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    m = sub.add_parser("measure", help="report busyness / nadir / ground for panoramas")
    m.add_argument("paths", nargs="+")
    m.set_defaults(func=cmd_measure)

    i = sub.add_parser("ingest", help="convert a raw panorama into a bundled 8K HEIC")
    i.add_argument("src")
    i.add_argument("name", help="bundle name, no extension (must match FarBackdrop)")
    i.add_argument("--exposure", type=float, default=0.0, help="stops, HDR sources")
    i.add_argument("--gamma", type=float, default=1.0, help=">1 darkens midtones")
    i.add_argument("--black", type=float, default=0.0, help="linear black-point subtract")
    i.add_argument("--quality", type=int, default=80)
    i.set_defaults(func=cmd_ingest)

    args = ap.parse_args()
    sys.exit(args.func(args) or 0)


if __name__ == "__main__":
    main()
