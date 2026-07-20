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
