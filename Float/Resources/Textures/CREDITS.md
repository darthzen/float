# Texture asset credits & licenses

Every bundled image asset is tracked here with its source, license, and the
attribution obligation it carries. **Public-domain** assets need no credit;
**CC BY 4.0** assets require a visible credit line in the shipping app.

---

## L1 backdrop (`Backdrop/`)

### Deep Star Maps 2020 — celestial, 8K equirectangular
- **File (raw):** `_raw/starmap_2020_8k.exr` — downloaded 2026-07-19
- **Dimensions / format:** 8192×4096, OpenEXR (HDR float, zip), 2:1 equirect
- **Source:** https://svs.gsfc.nasa.gov/vis/a000000/a004800/a004851/starmap_2020_8k.exr
- **Page:** https://svs.gsfc.nasa.gov/4851
- **Producer:** NASA/Goddard SFC Scientific Visualization Studio (released 2020-09-09)
- **Data:** 1.7B stars — Hipparcos-2, Tycho-2, Gaia DR2
- **License:** Public domain (NASA). No attribution required.
- **Suggested credit (courtesy):** "NASA/Goddard SVS. Gaia DR2: ESA/Gaia/DPAC."
- **Higher res available:** 16K / 32K / 64K EXR, and galactic-coordinate variants
  (`..._gal.exr`), same directory.
- **Pipeline:** EXR → tonemap/convert → ASTC; committed compressed asset lands in
  `Backdrop/`. (RealityKit can't load EXR directly.)

### Shutterstock royalty-free space skies — 8K equirectangular
Purchased royalty-free (Rick's Shutterstock license). Distinct backdrops the jump cycles
through with the NASA plate. Originals (12K–15K JPG) in `_raw/`; bundled as 8192×4096 HEIC.
- **License:** Shutterstock Standard royalty-free (per Rick's account). No public attribution
  required; usage per the Shutterstock license terms.
- `dual_nebula.heic` — shutterstock #2436644261 (red+blue dual nebula w/ bright star)
- `blue_filaments.heic` — shutterstock #2572761365 (cool blue filamentary field)
- `teal_orange.heic` — shutterstock #2626369537 (dense teal + orange nebula)
- `dark_dust.heic` — shutterstock #2651221149 (dark, sparse brown dust wisps)
- `pale_haze.heic` — shutterstock #2700631105 (soft pale-blue haze + star clusters)

---

## L2 nebula reference / sprite source (`Nebula/`)

> Note on use: sampling *colors* from these for the palette creates no derivative
> and carries no obligation. **Cutting them into sprite cards / textures that ship
> in the app IS a derivative work → the CC BY 4.0 credit line below must appear in
> the app.** Raw files not yet downloaded — URLs documented per Rick.

### Centaurus A (galaxy) — JWST / MIRI, mid-infrared
- **Flickr:** https://www.flickr.com/photos/nasawebbtelescope/55377597821/
- **Subject:** Centaurus A — dusty filaments, loops, warm-dust clouds (good palette
  + filament reference)
- **Credit:** NASA, ESA, CSA, STScI; Image Processing: Alyssa Pagan (STScI),
  Joseph DePasquale (STScI), Macarena Garcia Marin (ESA Office at STScI)
- **Posted:** 2026-07-06 (JWST 4th science anniversary)
- **License:** CC BY 4.0 (attribution required)
- **Original dimensions:** not stated on page — grab "Original" from Flickr sizes.

### Young Galaxy Cluster MACS J0553.4-3342 — JWST
- **Flickr:** https://www.flickr.com/photos/nasawebbtelescope/55380623885/
- **Subject:** merging galaxy cluster + gravitational-lensing arcs (mostly dark
  field w/ galaxies — weaker nebula reference than Centaurus A)
- **Credit:** ESA/Webb, NASA & CSA, S. Fujimoto
- **Posted:** 2026-07-07
- **License:** CC BY 4.0 (attribution required)
- **Original dimensions:** not stated on page — grab "Original" from Flickr sizes.

### Flame Nebula (NGC 2024) — JWST + Chandra X-ray  ★ best nebula reference
- **Flickr:** https://www.flickr.com/photos/nasawebbtelescope/55271979984/
- **Subject:** NGC 2024 star-forming region — an actual emission nebula; strong
  palette + filament/dust reference (most useful of the set for L2).
- **Credit:** X-ray: NASA/CXC/PSU/K. Getman, E. Feigelson, M. Kuhn & the MYStIX
  team; JWST: NASA, ESA, CSA, STScI, M. Meyer (U. Michigan), M. De Furio (UT
  Austin), M. Robberto (STScI), A. Pagan (STScI); Processing: NASA/CXC/SAO/L. Frattare
- **Posted:** 2026-05-15
- **License:** CC BY 4.0 (attribution required)
- **Original dimensions:** not stated on page — grab "Original" from Flickr sizes.

### Pillars of Creation (Eagle Nebula, M16) — JWST / NIRCam  ★ best nebula reference
- **Page:** https://esawebb.org/news/weic2216/
- **Image CDN:** https://cdn.esawebb.org/archives/images/screen/weic2216a.jpg
  (full-res available in the archive)
- **Subject:** iconic star-forming pillars in gas/dust — premier palette + filament
  + column-structure reference for L2.
- **Credit:** NASA, ESA, CSA, STScI; J. DePasquale, A. Koekemoer, A. Pagan (STScI)
- **Posted:** 2022-10-19
- **License:** CC BY 4.0 (ESA/Webb standard usage — attribution required).

### Carina Nebula / "Cosmic Cliffs" (NGC 3324) — JWST  ★ best nebula reference
- **Page:** https://science.nasa.gov/universe/stars/
- **Image:** https://assets.science.nasa.gov/dynamicimage/assets/science/astro/universe/internal_resources/402/Carina_Nebula-1.jpeg
- **Subject:** stellar-nursery cliffs/peaks — iconic palette + filament/dust
  reference; arguably the single best L2 reference of the set.
- **Credit:** NASA, ESA, CSA, STScI
- **License:** CC BY 4.0 (attribution required — confirm on STScI source).

### Lagoon Nebula (Messier 8) — Hubble / ACS  ★ good nebula reference
- **Page:** https://science.nasa.gov/mission/hubble/science/explore-the-night-sky/hubble-messier-catalog/messier-8/
- **Image:** https://assets.science.nasa.gov/dynamicimage/assets/science/missions/hubble/nebulae/emission/Hubble_M8_ACS_1_flat_FINAL.jpg
  (up to 7170×3836)
- **Subject:** emission nebula — pinkish-grey ionized gas + dark dust + embedded
  blue-white stars; strong palette + dust-lane reference for L2.
- **Credit:** NASA, ESA, M. Mutchler (STScI); Processing: Gladys Kober
  (NASA/Catholic University of America)
- **License:** CC BY 4.0 (Hubble/STScI standard — attribution required).

### Sagittarius B2 — JWST / MIRI (largest MW star-forming cloud)  ★ good nebula reference
- **Flickr:** https://www.flickr.com/photos/nasawebbtelescope/54809196576/
- **Subject:** Sgr B2 molecular cloud — dense, active star-forming region; rich
  filament + warm-dust palette reference for L2.
- **Credit:** NASA, ESA, CSA, STScI, Adam Ginsburg (U. Florida), Nazar Budaiev
  (U. Florida), Taehwa Yoo (U. Florida); Image Processing: Alyssa Pagan (STScI)
- **Posted:** 2025-09-24
- **License:** CC BY 4.0 (attribution required)
- **Original dimensions:** not stated on page — grab "Original" from Flickr sizes.

### Cranium Nebula — JWST (planetary nebula)  ★ good nebula reference
- **Flickr:** https://www.flickr.com/photos/nasawebbtelescope/55119073511/
- **Subject:** dying star expelling a gas shell with internal cloud structure —
  strong palette + shell/wisp reference for L2.
- **Credit:** NASA, ESA, CSA, STScI; Image Processing: Joseph DePasquale (STScI)
- **Posted:** 2026-02-27
- **License:** CC BY 4.0 (attribution required)
- **Original dimensions:** not stated on page — grab "Original" from Flickr sizes.

### Messier 82 / Cigar Galaxy — JWST + Hubble composite  [see note below — galaxy]
- **Flickr:** https://www.flickr.com/photos/nasawebbtelescope/55352876103/
- **Subject:** M82 starburst galaxy, edge-on; dusty outflow (decent dust-color
  reference, galaxy not nebula).
- **Credit:** NASA, ESA, CSA, Adam Smercina (STScI, Tufts), Thomas Williams
  (U. Manchester); Image Processing: Alyssa Pagan (STScI)
- **Posted:** 2026-06-23
- **License:** CC BY 4.0 (attribution required)
- **Original dimensions:** not stated on page — grab "Original" from Flickr sizes.

---

## Hero celestial body reference (§7c, `Bodies/CelestialBodies.swift`)

> These are single-viewpoint photos — **look/color reference only, NOT equirect
> wrap textures.** A sphere-mapped hero planet needs a 2:1 cylindrical map (source
> those separately, e.g. Solar System Scope / USGS maps). CC BY 4.0 credit applies
> if any derivative ships.

### Uranus — JWST (ice giant, rings)
- **Flickr:** https://www.flickr.com/photos/nasawebbtelescope/52797109227/
- **Subject:** Uranus with 11 of 13 rings + atmospheric features; reference for a
  hero Uranus.
- **Credit:** NASA, ESA, CSA, STScI; Image Processing: Joseph DePasquale (STScI)
- **Posted:** 2023-04-06
- **License:** **CC BY 2.0** (attribution required — note: 2.0, not 4.0)
- **Original dimensions:** not stated on page — grab "Original" from Flickr sizes.

### Jupiter — JWST (atmosphere, GRS, auroras)
- **Flickr:** https://www.flickr.com/photos/nasawebbtelescope/53268962997/
- **Subject:** Jupiter atmosphere — equatorial jet, Great Red Spot, auroras;
  reference for a hero Jupiter.
- **Credit:** NASA, ESA, CSA, STScI, R. Hueso (UPV/EHU), I. de Pater (UC Berkeley),
  T. Fouchet (Obs. Paris), L. Fletcher (U. Leicester), M. Wong (UC Berkeley),
  J. DePasquale (STScI)
- **Posted:** 2023-10-19
- **License:** **CC BY 2.0** (attribution required — note: 2.0, not 4.0)
- **Original dimensions:** not stated on page — grab "Original" from Flickr sizes.

### Saturn — JWST infrared (+ Hubble)
- **Flickr:** https://www.flickr.com/photos/nasawebbtelescope/55168418509/
- **Subject:** Saturn, rings + atmosphere, infrared — reference for a hero Saturn.
- **Credit:** NASA, ESA, CSA, STScI, Amy Simon (NASA-GSFC), Michael Wong (UC
  Berkeley); Image Processing: Joseph DePasquale (STScI)
- **Posted:** 2026-03-25
- **License:** CC BY 4.0 (attribution required)
- **Original dimensions:** not stated on page — grab "Original" from Flickr sizes.

### Neptune — JWST / NIRCam (rings)
- **Flickr:** https://www.flickr.com/photos/nasawebbtelescope/52374360534
- **Subject:** Neptune + rings in near-IR ("pearl" look) — reference for a hero Neptune.
- **Credit:** NASA, ESA, CSA, STScI
- **Posted:** 2022-09-21
- **License:** **CC BY 2.0** (attribution required)

### Mars — JWST / NIRCam (first Webb Mars)
- **Flickr:** https://www.flickr.com/photos/nasawebbtelescope/52369360300
- **Subject:** Mars disc (Syrtis Major, Hellas Basin, Huygens) + thermal map —
  reference for a hero Mars.
- **Credit:** NASA, ESA, CSA, STScI, Mars JWST/GTO team
- **Posted:** 2022-09-19
- **License:** **CC BY 2.0** (attribution required)

---

## Equirectangular WRAP-TEXTURE sources (public domain — preferred for §7c)

> These are true 2:1 cylindrical global maps — **directly usable as hero-planet
> sphere textures**, unlike the single-viewpoint Webb photos above. All public
> domain (NASA/USGS), so **no in-app attribution burden** — prefer these for the
> actual shipped planet textures; keep the CC BY Webb shots as look reference only.
> Not yet downloaded — links documented for the pipeline.

### Earth — NASA "Blue Marble" (Next Generation)
- **Source:** https://visibleearth.nasa.gov/collection/1484/blue-marble ·
  SVS: https://svs.gsfc.nasa.gov/3615/
- **Format:** equirectangular, up to 43200×21600; monthly cloud-free composites.
- **Credit (courtesy):** NASA Earth Observatory. **License:** Public domain.

### Mercury — MESSENGER MDIS global mosaic (USGS Astrogeology)
- **Source:** https://astrogeology.usgs.gov/search/map/mercury_messenger_mdis_basemap_enhanced_color_global_mosaic_665m
  (natural-color and MD3/enhanced variants available at same site)
- **Format:** equirectangular global mosaic, 665 m/px.
- **Credit (courtesy):** NASA/JHUAPL/Carnegie Institution/USGS. **License:** Public domain.

### Venus — Magellan radar mosaic + Mariner 10 clouds (USGS / JPL)
- **Surface map (equirect):** https://www.usgs.gov/media/images/venus-magellan-color-sar
- **Cloud-view reference:** Mariner 10, JPL PIA23791 —
  https://www.jpl.nasa.gov/images/pia23791-venus-from-mariner-10/
- **Note:** Venus's surface is cloud-hidden — a *realistic* hero Venus is a
  featureless yellow cloud ball (use Mariner-10 clouds), NOT the radar surface.
- **Credit (courtesy):** NASA/JPL / USGS. **License:** Public domain.

### Mars (alt, for texture) — Viking global color mosaic (USGS)
- **Source:** USGS Astrogeology "Mars Viking MDIM21 ClrMosaic global" (search
  astrogeology.usgs.gov) — PD equirect, better as a wrap texture than the Webb disc.
- **License:** Public domain.

---

## Hero star reference (§7c hero star; §184 sun rendering)

### The Sun — NASA SDO (solar flare)
- **Page:** https://science.nasa.gov/universe/stars/
- **Image:** https://assets.science.nasa.gov/dynamicimage/assets/science/astro/universe/internal_resources/496/Sun_Emits_Flare.jpeg
- **Subject:** active Sun with flare — reference for the emissive hero sun
  (granulation, corona, prominences per §184).
- **Credit (courtesy):** NASA/SDO. **License:** Public domain (no attribution required).
- **Note:** for a rotating hero sun you'll still want a procedural/emissive surface
  (§184) or an SDO equirect; this disc is look/color reference.

---

## Black hole & quasar reference (§7c hero object)

### Black-hole accretion disk — NASA SVS (Schnittman ray-trace)  ★ best hero-BH asset
- **Page:** https://svs.gsfc.nasa.gov/13326
- **Subject:** ray-traced supermassive black hole + accretion disk with
  gravitational lensing (the warped "top+bottom of disk visible" look).
- **Credit (courtesy):** NASA's Goddard SVS / Jeremy Schnittman.
- **License:** Public domain (no attribution required) — preferred for shipping.
- **Note:** delivered as video/GIF frames; pull a still frame for a texture, or
  use as motion reference for a shader-driven hero BH.

### M87* — Event Horizon Telescope (first black hole photograph)
- **Page:** https://eventhorizontelescope.org/ (polarised: https://www.eso.org/public/images/eso2105a/)
- **Subject:** real EHT image of M87's supermassive black hole (orange photon ring).
  Authentic but low-res/blurry — best as "the real thing" reference.
- **Credit:** EHT Collaboration.
- **License:** CC BY 4.0 (attribution required).

### Quasar "Tsunamis" — ESA/Hubble (artist's concept)
- **Page:** https://esahubble.org/images/opo2010a/
- **Subject:** artist's visualization — active quasar driving relativistic outflows
  from a central supermassive black hole. Good quasar look reference.
- **Format:** artwork (not a photo); 3840×2160, TIFF original (8.4 MB).
- **Credit:** NASA, ESA, and J. Olmsted (STScI).
- **License:** CC BY 4.0 (ESA/Hubble standard usage — attribution required).

### NGC 1275 / Perseus A — ESA/Hubble (AGN host galaxy)
- **Page:** https://esahubble.org/images/opo0314a/
- **Subject:** real photo of colliding galaxies + star birth around NGC 1275, a
  well-known AGN (supermassive-black-hole host). BH connection is *context*; the
  image itself is a galaxy/dust reference, not a black hole render.
- **Format:** photograph; 1489×2049, TIFF original (3.6 MB).
- **Credit:** NASA/ESA and The Hubble Heritage Team (STScI/AURA).
- **Posted:** 2003-05-01.
- **License:** CC BY 4.0 (ESA/Hubble standard usage — attribution required).

---

## Deep-sky feature imagery — L3 far objects (`_raw/deepsky/`)

Full-resolution masters for the distant galaxies / nebulae that hang in the far field
(§7c hero objects, L3 billboards). All downloaded 2026-07-23. Rick supplied NASA SVS
pages as the starting point; **SVS re-serves downscaled derivatives** (mostly 3840×2160
video frames), so each master below was traced back to the originating ESA/Hubble or
STScI release, which is 2–9× larger. SVS page IDs are noted for cross-reference.

**License (all ESA/Hubble items):** CC BY 4.0 — attribution required, credit line
unaltered and kept adjacent to the image. NASA SVS / STScI items are public domain.
Per the ESA/Hubble FAQ, individuals named in credit lines do **not** need to be
contacted; that clearance is what separates these from the rejected Fujii image below.

| File | Object | Dimensions | Release |
|---|---|---|---|
| `carina_hh901_mystic_mountain_heic1007c.tif` | HH 901 pillar, Carina Nebula | 7281×7149 | heic1007c |
| `m16_pillars_visible_heic1501a.tif` | Pillars of Creation, M16 — visible | 6780×7071 | heic1501a |
| `m16_pillars_infrared_heic1501b.tif` | Pillars of Creation, M16 — infrared | 3249×3045 | heic1501b |
| `m8_lagoon_visible_8kx8k.png` | Lagoon Nebula, M8 — visible | 8000×8000 | STScI/SVS 30943 |
| `m8_lagoon_infrared_8kx8k.png` | Lagoon Nebula, M8 — infrared | 8000×8000 | STScI/SVS 30943 |
| `s106_snow_angel_heic1118a.tif` | Sharpless 2-106 "snow angel" | 4356×3202 | heic1118a |
| `m104_sombrero_opo0328a.tif` | Sombrero Galaxy, M104 | 11472×6429 | opo0328a |
| `m106_heic1302a_7910x6178.tif` | Messier 106 / NGC 4258 | 7910×6178 | heic1302a |
| `ngc4631_whale_potw1146a.tif` | Whale Galaxy, NGC 4631 (edge-on) | 8933×2434 | potw1146a |
| `m31_andromeda_phat_10k_heic1502a.tif` | Andromeda, M31 — PHAT mosaic | 10000×3197 | heic1502a |
| `milkyway_360_panorama_eso0932a.tif` | Milky Way 360° panorama | 6000×3000 | eso0932a |

### Credit lines (must ship verbatim if the asset ships)
- **HH 901 / Mystic Mountain** (heic1007c, SVS 30940) — https://esahubble.org/images/heic1007c/
  "NASA, ESA and M. Livio and the Hubble 20th Anniversary Team (STScI)"
- **M16 Pillars of Creation** (heic1501a/b, SVS 31007) — https://esahubble.org/images/heic1501a/
  "NASA, ESA/Hubble and the Hubble Heritage Team"
- **M8 Lagoon Nebula** (SVS 30943) — https://svs.gsfc.nasa.gov/30943/
  "NASA, ESA, and STScI" — public domain. Hubble's 28th-anniversary image.
  Note: these are the 8K×8K STScI source plates, *larger* than the ESA/Hubble
  release (heic1808a, 4782×6028), so SVS is the better source for this one.
- **Sharpless 2-106** (heic1118a, SVS 30682) — https://esahubble.org/images/heic1118a/
  "NASA & ESA"
- **M104 Sombrero** (opo0328a, SVS 30995) — https://esahubble.org/images/opo0328a/
  "NASA/ESA and The Hubble Heritage Team (STScI/AURA)"
- **M106** (heic1302a, SVS 31021) — https://esahubble.org/images/heic1302a/
  "NASA, ESA, the Hubble Heritage Team (STScI/AURA), and R. Gendler (for the Hubble
  Heritage Team); Acknowledgment: J. GaBany"
  ⚠️ Contains amateur data composited by Gendler/GaBany. It is an official ESA/Hubble
  release under CC BY 4.0 and the FAQ clears reuse, but the credit line is longer than
  usual and must not be trimmed.
- **NGC 4631 Whale** (potw1146a, SVS 31016) — https://esahubble.org/images/potw1146a/
  "NASA & ESA"
- **M31 Andromeda** (heic1502a, SVS 30990) — https://esahubble.org/images/heic1502a/
  "NASA, ESA, J. Dalcanton (University of Washington, USA), B. F. Williams (University
  of Washington, USA), L. C. Johnson (University of Washington, USA), the PHAT team,
  and R. Gendler."
  Note: this is the 10K publication TIFF. The true original is 69536×22230 (4.3 GB
  PSB) with a 40K TIFF (1.7 GB) intermediate — both available if 10K proves too soft.
  It covers ~⅓ of the disc, not the whole galaxy; for a full-disc M31 billboard the
  SVS 30990 wide view (NOAO ground-based optical, 3840×2160) is the fallback.
- **Milky Way 360° panorama** (eso0932a) — https://www.eso.org/public/images/eso0932a/
  "ESO/S. Brunier" — CC BY 4.0. GigaGalaxy Zoom project, 2009.

### ⚠️ eso0932a resolves the §287 / §11 open question — and it is too small
The spec (§287) lists the ESO Milky Way panorama as an L1 backdrop candidate with
"license + resolution must be verified before shipping". Now verified:
- **License: fine** — CC BY 4.0, credit "ESO/S. Brunier".
- **Resolution: fails the spec target.** The public original is **6000×3000**, well
  under §4's 8K–16K equirect requirement, and *below* the Deep Star Maps plate already
  bundled (8192×4096, with 16K/32K/64K available). The 800-megapixel version referenced
  in the press release is not published — ESO directs requests to Brunier privately.
- **Conclusion:** keep Deep Star Maps as the L1 plate. eso0932a is still useful as a
  *look* reference (it is real astrophotography of the band, in galactic coordinates,
  2:1 equirect and seam-clean) but should not be upscaled into a shipping backdrop.

### Survey note — the ESO 360° panorama archive
https://www.eso.org/public/images/archive/category/360pano/ (459 images) was enumerated
from the catalogue embedded in the `viewall` page: 250 entries recovered, 138 true 2:1
equirectangular. Exactly one (eso0932a) is deep-sky; every other is a ground-level
panorama — Paranal/La Silla/ALMA/Chajnantor sites, ESO HQ interiors, ESO Supernova.

⚠️ **This note originally concluded "all unusable — do not re-survey."** That was written
under the no-ground reading of the premise. Rick relaxed that gate on 2026-07-23 (a static
horizon is a vection rest frame and a vertigo mitigation, not a violation of §9), so the
night-sky subset is now live — see **Grounded night-sky backdrops** below. The interiors
and daytime shots remain out.

---

## Grounded night-sky backdrops (`_raw/grounded/`) — vertigo-mitigation option

For viewers who get vertigo in an all-sky float, a static horizon gives the vestibular
system a rest frame. These are full-sphere 2:1 equirects that drop straight onto the
existing `FarBackdrop` inward sphere with no code change.

### ⚠️ The trap: most ESO "-extended" panoramas are black-padded at the nadir
ESO pads partial-sphere captures out to a nominal 2:1 with **pure black fill**. The
catalogue reports 2.000 aspect for all of them, so this is invisible until you measure it.
Measured nadir black fraction across the night-sky candidates:

| Candidate | Nadir black | Verdict |
|---|---|---|
| `150119-3p6-airglow-eq-extended` | 47.9% | ✗ reject |
| `150119cesta-airglow-eq-extended` | 46.5% | ✗ reject |
| `150123-24_atacama_fullfr_cc-eq-ext` | 44.7% | ✗ reject (also has an identifiable person) |
| `potw2514c` | 43.4% | ✗ reject |
| `uhd-9428-panorama-eq-extended` | 41.4% | ✗ reject |
| `150126vlt2-dal-jup-eq-extended` | 40.0% | ✗ reject |
| `nik9850p1-cc-extended` | 38.3% | ✗ reject |
| `potw1224a-ext` | 32.4% | ✗ reject |
| `2016_04_06_VISTA_night_Pano-VTversion_CC` | 29.3% | ✗ reject |
| `2016_04_09_ALMA_Central_Array_Reproj-CC` | 28.7% | ✗ reject |
| `2016-04-03-paranal-vlt-360fd-extended-cc` | 27.5% | ✗ reject |
| `brammer-nightmoon-eq-ext` | 8.6% | ✗ reject (twilight/moonlit, reads as daytime) |
| **`ESO_Paranal_360_Marcio_Cabral_Chile_09-CC`** | **0.0%** | ✓ **keep** |
| **`ESO_Paranal_360_Marcio_Cabral_Chile_10-CC`** | **0.0%** | ✓ **keep** |
| **`2019-06-30-FSLaSillaBTW-3p6-And-NTT-EQproj-CC`** | **0.0%** | ✓ **keep** |
| **`2019-07-02-ExTra-Airglow-360Pano-24mm-EQ-CC`** | **0.0%** | ✓ **keep** |

Rejected ones look down onto a black void with a hard circular edge — which destroys the
very rest frame the ground is there to provide. **Always measure the nadir before adopting
an ESO panorama.** Reproduce with the check in `scripts/` or: downsample to 64×512 luma,
count bottom rows where `max(row) <= 6`.

### Kept — ESO Atacama night panoramas (CC BY 4.0)
- `paranal_vlt_milkyway_cabral09_26k.jpg` — 26162×13081. Milky Way over the VLT platform.
  **Credit: "M. Cabral/ESO"** — https://www.eso.org/public/images/ESO_Paranal_360_Marcio_Cabral_Chile_09-CC/
- `paranal_vlt_milkyway_cabral10_26k.jpg` — 25786×12893. *"The VLT points up into the Milky
  Way"* — laser guide stars firing. **Credit: "M. Cabral/ESO"**
- `lasilla_milkyway_arc_2019_23k.jpg` — 23384×11692. *"Milky Way arc above La Silla."*
  **Credit: "P. Horálek/ESO"**
- `lasilla_extra_airglow_2019_24k.jpg` — 23692×11846. *"Two Milky Way lightning strikes"* —
  ExTrA domes, twin Milky Way limbs, strong airglow. **Credit: "P. Horálek/ESO"**

Credit order matters: ESO writes these **photographer-first** ("M. Cabral/ESO"), not
"ESO/M. Cabral". Reproduce the string as-is.

These are the `cdn.eso.org/images/large/<id>.jpg` files, which for this archive are served
at **full catalogue resolution** — not downscaled. The `original` TIFFs are the same pixels
at ~358 MB each; the JPEGs are the practical master.

⚠️ ESO CC BY 4.0 carries two live exceptions: the **ESO logo** is protected, and
**commercial use of images with identifiable people is prohibited**. All four kept images
were checked for people; `150123-24_atacama` was rejected partly on that basis. Telescope
domes carry ESO branding — fine as photographic content, but do not crop a logo out as a
standalone mark.

### Kept — Poly Haven night HDRIs (CC0, no attribution required)
True full-sphere, real HDR, no black padding, and **CC0** — the cleanest licensing in this
entire file. Downloaded at 8K to match §4's backdrop budget; 16K and 24K are available.
- `rogland_clear_night_8k.hdr` — 8192×4096 Radiance RGBE (24576×12288 max).
  Strong Milky Way arch over dark rocky desert, **no buildings or hardware**. Best fit if
  the goal is "grounded but not a specific real place."
  Author: Greg Zaal. https://polyhaven.com/a/rogland_clear_night
- `dikhololo_night_8k.hdr` — 8192×4096 Radiance RGBE (24576×12288 max).
  Milky Way over dark scrub with tree silhouettes; warmer, softer horizon glow.
  Author: Greg Zaal. https://polyhaven.com/a/dikhololo_night

Courtesy credit "HDRI from Poly Haven (CC0)" is appreciated but **not legally required**.

⚠️ Poly Haven's `night` tag is unreliable — over half the 59 tagged assets are moonlit or
twilight and read as blue daylight (`clarens_night_01`, `kloppenheim_02`,
`narrow_moonlit_road`, `qwantani_moonrise`). Preview before adopting; only the two above
survived a visual pass.

### Shipped assets (bundled 2026-07-23)
All six are ingested to **8192×4096 HEIC** in `Backdrop/` via
`scripts/backdrop_tool.py ingest`, which is reproducible — rerun the exact command to
regenerate. `busyness` below is the measured value carried in `FarBackdrop.catalog`.

| Bundled asset | Source | Ingest command | busyness |
|---|---|---|---|
| `ground_rogland_night.heic` | `rogland_clear_night_8k.hdr` | `ingest --exposure -3.0` | 0.55 |
| `ground_dikhololo_night.heic` | `dikhololo_night_8k.hdr` | `ingest --exposure -1.0` | 0.63 |
| `ground_paranal_vlt.heic` | `paranal_vlt_milkyway_cabral09_26k.jpg` | `ingest` | 0.84 |
| `ground_paranal_lasers.heic` | `paranal_vlt_milkyway_cabral10_26k.jpg` | `ingest` | 0.65 |
| `ground_lasilla_arc.heic` | `lasilla_milkyway_arc_2019_23k.jpg` | `ingest` | 0.89 |
| `ground_lasilla_airglow.heic` | `lasilla_extra_airglow_2019_24k.jpg` | `ingest` | 1.00 |

The two HDRIs need **negative** exposure: they are real HDR, and an untonemapped
(or sips-default) conversion lifts the ground until the scene reads as dusk. Exposure
was picked so the ground stays *readable* rather than crushed to silhouette — a black
ground gives a horizon line but no texture, which weakens the rest frame that is the
whole reason these are here. `dikhololo` was captured darker and needed +2 stops
relative to `rogland`.

### Open design consequences of shipping a grounded mode
Not blockers, but a ground plane interacts with three existing systems:
1. **§7b hyperspace jump** — with a horizon present the jump must either keep the ground
   static (breaks the fiction) or move it (destroys the rest frame, and is *worse* for
   comfort than the current design). Grounded presets likely need the jump replaced with a
   cross-fade. This is the biggest one.
2. **§4 L2 nebula volume** — a surrounding splat/particle volume will clip through the
   horizon. Needs an above-horizon clamp in grounded presets.
3. **§7d drift + debris** — ambient objects and debris on paths below the horizon will read
   as passing "underground." Needs culling against the horizon plane.

---

## ⛔ Rejected — licensing not acceptable

### Scorpius / Milky Way center — Akira Fujii (via ESA/Hubble)
- **Page:** https://esahubble.org/images/heic0211e/
- **Credit:** Akira Fujii (third-party photographer, not ESA/Hubble's own work).
- **Why rejected:** ESA/Hubble's CC BY 4.0 policy **excludes** third-party images
  like this one; it's copyrighted to the individual and needs explicit permission.
  **Do not use.** The Milky Way band is already covered by the public-domain NASA
  Deep Star Maps (see L1 backdrop above), so no need to chase permission.

---

## Other / phenomena reference (§6)

### Tycho Supernova Remnant — Chandra X-ray + DSS optical
- **Page:** https://science.nasa.gov/universe/stars/
- **Image:** https://assets.science.nasa.gov/dynamicimage/assets/science/astro/universe/internal_resources/403/Tycho-1.jpeg
- **Subject:** SN 1572 remnant, ~13,000 ly (Cassiopeia) — reference for a supernova-
  remnant hero object / phenomenon.
- **Credit:** X-ray: NASA/CXC/RIKEN & GSFC/T. Sato et al.; Optical: DSS.
- **License:** Public domain (NASA/CXC; credit by convention).

---

## ⚠️ Test / experimental — imported Apple Spatial environments

### `imported_spatial_1…5.heic` — Shutterstock 360° HDRIs (Apple Spatial exports)
- **Source:** exported via Spatial Media Toolkit (dropdown: *Apple Spatial*) from Shutterstock
  360° HDRIs; originals at repo root as `shutterstock_<id>_spatial.public.heic`.
- **Format:** Apple Spatial **stereo** 360° equirectangular HEIC — CGImage index 0 = left eye,
  index 1 = right eye (`StereoPair`, disparity 0). Cycled via `SpatialImageEnvironment` for an
  A/B against the generated scene; currently rendered MONO (primary eye) pending a stereo material.
  - `imported_spatial_1` — id 2436644261 (Jurik Peter) — 12000×6000/eye
  - `imported_spatial_2` — id 2572761365 — 15000×7500/eye
  - `imported_spatial_3` — id 2626369537 — 12000×6000/eye
  - `imported_spatial_4` — id 2651221149 — 12000×6000/eye
  - `imported_spatial_5` — id 2700631105 — 12000×6000/eye
- **Embedded notice:** "Copyright (c) 2024 …/Shutterstock. No use without permission."
- **License:** ⚠️ **NOT cleared for distribution.** In-repo as comparison test assets only.
  Confirm the Shutterstock license (and whether it permits shipping) before any of these go in
  a build that leaves Rick's device. Remove or replace if not licensed for redistribution.
