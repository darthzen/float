#!/usr/bin/env python3
"""Render the Float app icon — a classic red/white fishing bobber floating on water.

visionOS app icons are LAYERED (back/middle/front, each 1024×1024); the system
composites them with parallax + a circular glass mask on the Home View. We render:
  back   — sky→water vertical gradient (opaque, fills the icon)
  middle — concentric water ripples around the bobber's waterline (transparent)
  front  — the bobber sphere, red top / white bottom, glossy (transparent bg)

Drawn at 2× and downsampled for clean anti-aliasing.
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SS = 2                      # supersample
N = 1024 * SS
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "icon_layers")
os.makedirs(OUT, exist_ok=True)


def save(arr_or_img, name):
    im = arr_or_img if isinstance(arr_or_img, Image.Image) else Image.fromarray(arr_or_img)
    im = im.resize((1024, 1024), Image.LANCZOS)
    im.save(os.path.join(OUT, name))
    print("wrote", name, im.size, im.mode)


# ── back: sky → water gradient ──────────────────────────────────────────────
def back():
    top = np.array([150, 205, 235], float)     # light sky blue
    horizon = np.array([120, 185, 220], float)
    deep = np.array([28, 78, 120], float)       # deep water
    y = np.linspace(0, 1, N)[:, None]
    # sky in the upper 55%, water below, with a soft horizon blend
    horizon_y = 0.55
    sky = top + (horizon - top) * (y / horizon_y).clip(0, 1)
    water = horizon + (deep - horizon) * ((y - horizon_y) / (1 - horizon_y)).clip(0, 1)
    col = np.where(y < horizon_y, sky, water)
    img = np.repeat(col[:, None, :], N, axis=1).astype(np.uint8)
    return Image.fromarray(img, "RGB").convert("RGBA")


# ── middle: water ripples around the waterline ──────────────────────────────
def middle():
    im = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx, cy = N // 2, int(N * 0.66)              # waterline, under the bobber
    for i, r in enumerate(range(int(N * 0.16), int(N * 0.44), int(N * 0.055))):
        a = int(70 * (1 - i / 5))
        ry = int(r * 0.32)                       # flattened = seen at a shallow angle
        d.ellipse([cx - r, cy - ry, cx + r, cy + ry], outline=(230, 245, 255, a),
                  width=max(2, int(N * 0.006)))
    return im.filter(ImageFilter.GaussianBlur(N * 0.004))


# ── front: the bobber ───────────────────────────────────────────────────────
def front():
    cx, cy, R = N / 2, N * 0.47, N * 0.30
    yy, xx = np.mgrid[0:N, 0:N].astype(float)
    dx, dy = (xx - cx) / R, (yy - cy) / R
    r2 = dx * dx + dy * dy
    inside = r2 <= 1.0
    z = np.sqrt(np.clip(1 - r2, 0, 1))          # sphere normal z
    # light from upper-left
    L = np.array([-0.5, -0.6, 0.62]); L = L / np.linalg.norm(L)
    shade = (dx * L[0] + dy * L[1] + z * L[2]).clip(0, 1)
    shade = 0.55 + 0.45 * shade                 # lift ambient so the white reads white

    red = np.array([210, 46, 44], float)
    white = np.array([250, 250, 248], float)
    equator = dy > 0.06                          # lower part = white, upper = red
    base = np.where(equator[..., None], white, red)
    col = (base * shade[..., None]).clip(0, 255)

    # thin dark band at the equator
    band = np.abs(dy) < 0.055
    col[band & inside] = (col[band & inside] * 0.45)
    # specular highlight upper-left
    spec = np.exp(-(((dx + 0.42) ** 2 + (dy + 0.42) ** 2)) / 0.045) * 200
    col = (col + spec[..., None]).clip(0, 255)

    rgba = np.zeros((N, N, 4), np.uint8)
    rgba[..., :3] = col.astype(np.uint8)
    rgba[..., 3] = np.where(inside, 255, 0).astype(np.uint8)
    im = Image.fromarray(rgba, "RGBA")

    # top stem + antenna
    d = ImageDraw.Draw(im)
    sx = cx
    d.rectangle([sx - N * 0.020, cy - R - N * 0.055, sx + N * 0.020, cy - R + N * 0.02],
                fill=(60, 60, 66, 255))
    d.ellipse([sx - N * 0.035, cy - R - N * 0.085, sx + N * 0.035, cy - R - N * 0.02],
              outline=(60, 60, 66, 255), width=max(3, int(N * 0.008)))
    # soft contact shadow on the water (helps it read as floating)
    sh = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ds = ImageDraw.Draw(sh)
    ds.ellipse([cx - R * 0.9, cy + R * 0.55, cx + R * 0.9, cy + R * 0.95],
               fill=(10, 30, 50, 90))
    sh = sh.filter(ImageFilter.GaussianBlur(N * 0.012))
    return Image.alpha_composite(sh, im)


save(back(), "back.png")
save(middle(), "middle.png")
save(front(), "front.png")
# a flat composite too, for a quick preview / any non-layered slot
flat = Image.alpha_composite(Image.alpha_composite(back(), middle()), front())
save(flat, "flat_preview.png")
