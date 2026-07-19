# Backdrop — L1 far backdrop (§4)

Equirectangular panoramas for the inward `FarBackdrop` sphere (`DepthLayers.swift`).

**Format:**
- Equirectangular, **2:1 aspect** (e.g. 8192×4096 or 16384×8192).
- Ship as ASTC-compressed (§4). Source can be PNG/EXR/HEIC in `_raw/`; the
  committed asset here should be the compressed version.
- One seam runs down the back of the sphere — a proper 2:1 equirect hides it.

**License-clean sources:**
- NASA SVS "Deep Star Maps 2020" — public domain, purpose-built equirect starfield.
- ESO Milky Way panorama (Brunier / Guisard) — CC BY 4.0 (credit required).

Record source + license for every file in `../CREDITS.md`.
