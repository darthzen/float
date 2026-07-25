#!/usr/bin/env python3
"""Generate deepsky_auto.json: a deepsky_pipeline manifest row for every sky-worthy
image in _raw/potm (the ESA/Webb POTM + hand-picked pulls, see scripts/fetch_potm.py).

Classification MEASURES THE IMAGE: whether the subject runs off the frame edge is the
only question the two recipes actually differ on, so it is answered by the master's own
border content, not by words in its title. (Round 6: "Heart of the Phantom Galaxy" has
no field keyword, so a full-frame galaxy whose arms run past every edge was built with
the on-black object recipe — flat fill + starfield prompt — and the galaxy ended in a
hard box. Three others were wrong the same way, one in the opposite direction.) Titles
still decide the PLANET case, which needs ghost-planet suppression regardless. Rows carry
first-guess placement params per class — same philosophy as the hand-tuned MANIFEST
rows: they render fine and get nudged on device. Engineering/PR shots (rocket liftoff,
detector mosaics, side-by-side comparisons) are skipped outright.

Also emits deepsky_auto_catalog.swift — the SpatialImageEnvironment.catalog lines —
so the Swift registry can be pasted, not hand-typed.

Run:  python3 upscale/potm_auto_manifest.py     # rewrites both outputs, prints a table
"""
import html
import json
import os
import re

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
POTM = os.path.join(REPO, "Float/Resources/Textures/_raw/potm")
MANIFEST = os.path.join(POTM, "potm_manifest.json")
OUT_JSON = os.path.join(HERE, "deepsky_auto.json")
OUT_SWIFT = os.path.join(HERE, "deepsky_auto_catalog.swift")

Image.MAX_IMAGE_PIXELS = None

# Non-sky imagery: engineering, alignment, PR. Never scenes.
SKIP = {
    "potm2201a": "rocket liftoff photo",
    "potm2202a": "mirror-alignment detector mosaic",
    "potm2205a": "MIRI/Spitzer side-by-side comparison panel",
    "potm2206":  "FGS engineering test mosaic",
}

PLANET_KW = ("saturn", "jupiter", "uranus", "neptune", "titan ")
# Device-approved per-scene param overrides — survive regeneration (2026-07-24:
# Saturn fov 45->95, "big and majestic" per Rick; was hand-edited in the json and
# a regen clobbered it once).
OVERRIDES = {
    # desc: sky360 prompt override — naming Saturn in the outpaint prompt made the
    # model hallucinate EXTRA ringed planets around it (object batch 1)
    "saturn1": {"fov_x": 95, "desc": "empty deep space"},
}
FIELD_KW = ("nebula", "cloud", "cliffs", "pillars", "region", "complex", "perseus",
            "sagittarius", "rho ophiuchi", "dust", "n79", "star-forming", "star formation",
            "nursery", "serpens", "orion", "carina", "tarantula", "chamaeleon", "digel",
            "protostar", "westerlund", "ism", "hourglass", "l1527", "herbig")
# params per class — fields fill the forward view, objects hang in the void (§ deepsky
# pipeline docstring; numbers bracket the device-approved hand-tuned rows).
PARAMS = {
    "planet": dict(fov_x=45,  lon=0, lat=0, feather=0.12, exposure=0.2),
    "field":  dict(fov_x=130, lon=0, lat=0, feather=0.30, exposure=0.35),
    "object": dict(fov_x=85,  lon=0, lat=0, feather=0.14, exposure=0.25),
}


# Border-median luminance (0-255) below which the subject is judged to sit ON BLACK,
# and above which it is judged to RUN OFF the frame. Between them the measurement is not
# decisive and the old title keywords break the tie. Measured spread over the real
# library is bimodal with a wide empty middle, so the exact cut is not delicate.
# Measured over the real library these land in two tight clusters with NOTHING between
# 23 and 55, so the cut is not delicate; the band below just refuses to guess if a
# future master ever lands in the gap.
BORDER_ON_BLACK = 25.0
BORDER_RUNS_OFF = 45.0


def border_level(path):
    """Brightest of the master's four edge medians. High = the subject is cut off by the
    frame and diffusion must CONTINUE it outward (field recipe: mirror-tiled structural
    fill, anchored denoise, continuation prompt). Low = the subject hangs on black and
    diffusion should paint starfield around it, not extend it (object recipe: flat
    border-median fill, high denoise, starfield prompt).

    MAX, not mean, over the four edges: a wide crop of a discrete object has two long
    dark edges that outvote the two short ones, so averaging called the Sombrero and
    Centaurus A "runs off the edge" purely because they are letterboxed."""
    import numpy as np
    with Image.open(path) as im:
        im = im.convert("RGB")
        im.thumbnail((512, 512), Image.LANCZOS)
        a = np.asarray(im, np.float32).mean(2)
    k = max(2, min(a.shape) // 24)
    return float(max(np.median(a[:k]), np.median(a[-k:]),
                     np.median(a[:, :k]), np.median(a[:, -k:])))


def classify(title, path=None):
    t = title.lower()
    if any(k in t for k in PLANET_KW):
        return "planet"
    kw = "field" if any(k in t for k in FIELD_KW) else "object"
    if path is None:
        return kw
    b = border_level(path)
    if b < BORDER_ON_BLACK:
        return "object"
    if b > BORDER_RUNS_OFF:
        return "field"
    return kw


def main():
    with open(MANIFEST) as f:
        entries = json.load(f)
    # Scenes pruned in device triage (scripts/prune_scenes.py) — never resurrect.
    pruned_path = os.path.join(HERE, "pruned_scenes.json")
    pruned = set(json.load(open(pruned_path))) if os.path.exists(pruned_path) else set()
    rows, skipped = [], []
    for e in entries:
        pid = e["id"]
        title = html.unescape(e["title"]).strip()
        if pid in pruned:
            skipped.append((pid, "pruned in device triage"))
            continue
        if pid in SKIP:
            skipped.append((pid, SKIP[pid]))
            continue
        ext = os.path.splitext(e["url"].split("?")[0])[1] or ".tif"
        src = os.path.join(POTM, pid + ext)
        rel = f"../potm/{pid}{ext}"
        if not os.path.exists(src):
            # Non-SR originals live only on the archive drive; masters that went
            # through master_sr.py exist locally as potm_sr outputs — same aspect,
            # full density. Fall back to those rather than dropping the row.
            sr = os.path.join(os.path.dirname(POTM), "potm_sr", f"{pid}.png")
            if not os.path.exists(sr):
                skipped.append((pid, "file missing (original archived, no potm_sr)"))
                continue
            src, rel = sr, f"../potm_sr/{pid}.png"
        with Image.open(src) as im:
            w, h = im.size
        cls = classify(title, src)
        kind = "object" if cls == "planet" else cls
        p = dict(PARAMS[cls])
        if cls == "field" and h > w * 1.1:
            p["rot"] = 1          # vertically-composed field -> horizontal nebula bank
        # Wide panoramics span most of the sphere at natural proportions (device
        # feedback 2026-07-24, third round: even 180-270deg equidistant wraps read as
        # wider shots, not wraparound — every scene is now a FULL 360 sky via the
        # sky360 outpaint path; immersion over accuracy). fov_x here is PLACEMENT on
        # the 360 canvas, capped at 320 so the outpaint closes the back of the sphere
        # instead of butting the master's own ends together.
        # Aspect ratio sets PLACEMENT (how much sphere a wide pano should span); the
        # border measurement above sets the RECIPE. Conflating them is what promoted an
        # on-black master to the field fill just for being wide.
        ar = (max(w, h) if p.get("rot") else w) / (min(w, h) if p.get("rot") else h)
        if cls != "planet" and ar >= 1.9:
            p.update(fov_x=max(180, min(320, round(80 * ar))),
                     feather=0.30 if kind == "field" else p["feather"],
                     exposure=0.35 if kind == "field" else p["exposure"])
        p.update(OVERRIDES.get(pid, {}))
        rows.append({"name": f"spatial_{pid}", "rel": rel,
                     "kind": kind, "params": p, "title": title})
        print(f"{pid:<30} {cls:<7} {w}x{h}  {title[:58]}")

    with open(OUT_JSON, "w") as f:
        json.dump(rows, f, indent=1)

    with open(OUT_SWIFT, "w") as f:
        f.write("// Auto-generated by upscale/potm_auto_manifest.py — POTM catalog entries.\n")
        for r in rows:
            t = r["title"].replace('"', "'")
            t = re.sub(r"\s*\((?:NIRCam|MIRI)[^)]*\)$", "", t)  # trim instrument suffixes
            if len(t) > 44:
                t = t[:43].rstrip() + "…"
            f.write(f'        .init(name: "{r["name"]}", title: "{t}", grounded: false),\n')

    print(f"\n{len(rows)} rows -> {OUT_JSON}")
    for pid, why in skipped:
        print(f"SKIPPED {pid}: {why}")


if __name__ == "__main__":
    main()
