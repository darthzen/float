#!/usr/bin/env python3
"""Fetch unWISE W1/W2 all-sky equirect (CAR) FITS from CDS hips2fits.

The HiPS pyramid (CDS/P/unWISE/W1, /W2 — FITS tiles, real coadd flux) does the
2.75"/px -> ~105"/px downsample server-side, so a 12288x6144 galactic-frame CAR
render is a handful of HTTP requests, not an 18,240-tile mosaic. hips2fits caps
requests at 50 Mpx, so the full-res pull is striped: 4 latitude strips of
12288x1536 per band (~75 MB FITS each, 8 strips total). Compose stage:
upscale/allsky_rgb.py.

Stages (resumable — strips already on disk at expected size are skipped):

  python3 scripts/fetch_unwise.py test      # one 512x256 strip; validates the
                                            # wcs-JSON + GLON-CAR request shape
  python3 scripts/fetch_unwise.py preview   # 4096x2048 per band (~33 MB each)
  python3 scripts/fetch_unwise.py fetch     # 8 full-res strips (~600 MB total)

Frame: galactic, galactic center at the image center column (faces -Z at app
launch), CDELT1 < 0 = standard sky-seen-from-inside parity — verify chirality
at preview against the shipped SPHEREx map before the full fetch.
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
OUT = os.path.join(REPO, "Float/Resources/Textures/_raw/unwise/fits")
UA = "Mozilla/5.0 (Float unWISE fetcher; rick@theashfords.org)"
SERVICES = [
    "https://alasky.cds.unistra.fr/hips-image-services/hips2fits",
    "https://alaskybis.cds.unistra.fr/hips-image-services/hips2fits",
]
BANDS = {"W1": "CDS/P/unWISE/W1", "W2": "CDS/P/unWISE/W2"}
FULL_W, FULL_H = 12288, 6144
N_STRIPS = 4  # 12288x1536 = 18.9 Mpx/strip, under the 50 Mpx request cap
PREVIEW_W, PREVIEW_H = 4096, 2048


def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def strip_wcs(width, height, row0=0, full_h=None):
    """CAR galactic WCS for a horizontal strip whose bottom FITS row is global
    row0 (0-based, bottom-up). CRVAL2 must stay 0 for CAR, so the latitude
    band is selected purely via CRPIX2."""
    full_h = full_h or height
    step = 360.0 / width
    return {
        "NAXIS1": width, "NAXIS2": height, "WCSAXES": 2,
        "CTYPE1": "GLON-CAR", "CTYPE2": "GLAT-CAR",
        "CUNIT1": "deg", "CUNIT2": "deg",
        "CRVAL1": 0.0, "CRVAL2": 0.0,
        "CDELT1": -step, "CDELT2": step,
        "CRPIX1": width / 2 + 0.5, "CRPIX2": full_h / 2 + 0.5 - row0,
    }


def expected_bytes(width, height):
    """FITS: 2880-byte header block(s) + big-endian float32 data, 2880-padded.
    Lower bound (>= 1 header block) is enough for resume/size checks."""
    data = width * height * 4
    return 2880 + ((data + 2879) // 2880) * 2880


def fetch_one(hips, wcs, dst):
    """Download one hips2fits FITS render, atomically, with mirror fallback."""
    if os.path.exists(dst) and os.path.getsize(dst) >= expected_bytes(wcs["NAXIS1"], wcs["NAXIS2"]):
        log(f"  skip {os.path.basename(dst)} (present)")
        return 0
    q = urllib.parse.urlencode({"hips": hips, "format": "fits", "wcs": json.dumps(wcs)})
    mpx = wcs["NAXIS1"] * wcs["NAXIS2"] / 1e6
    part = dst + ".part"
    for attempt in range(6):
        svc = SERVICES[min(attempt // 3, 1)]  # 3 tries primary, then mirror
        try:
            t0 = time.time()
            req = urllib.request.Request(f"{svc}?{q}", headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=900) as r, open(part, "wb") as f:
                while chunk := r.read(1 << 20):
                    f.write(chunk)
            os.replace(part, dst)
            mb = os.path.getsize(dst) / 1e6
            log(f"  {os.path.basename(dst)}: {mb:.0f} MB ({mpx:.1f} Mpx) in {time.time()-t0:.0f}s")
            return mb
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            wait = 15 * (attempt + 1)
            log(f"  !! {os.path.basename(dst)} attempt {attempt+1} ({svc.split('/')[2]}): {e} — retry in {wait}s")
            time.sleep(wait)
    raise RuntimeError(f"all attempts failed for {dst}")


def run(stage):
    os.makedirs(OUT, exist_ok=True)
    if stage == "test":
        wcs = strip_wcs(512, 128, row0=64, full_h=256)  # off-center strip: exercises CRPIX2 math
        fetch_one(BANDS["W1"], wcs, os.path.join(OUT, "W1_test.fits"))
        return
    if stage == "preview":
        for band, hips in BANDS.items():
            fetch_one(hips, strip_wcs(PREVIEW_W, PREVIEW_H),
                      os.path.join(OUT, f"{band}_preview.fits"))
        return
    # fetch: 4 strips x 2 bands, bottom-up
    sh = FULL_H // N_STRIPS
    total = 0
    for band, hips in BANDS.items():
        for s in range(N_STRIPS):
            wcs = strip_wcs(FULL_W, sh, row0=s * sh, full_h=FULL_H)
            total += fetch_one(hips, wcs, os.path.join(OUT, f"{band}_strip{s}.fits")) or 0
    log(f"DONE — fetched {total:.0f} MB this run -> {OUT}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("stage", choices=["test", "preview", "fetch"])
    args = ap.parse_args()
    run(args.stage)
    return 0


if __name__ == "__main__":
    sys.exit(main())
