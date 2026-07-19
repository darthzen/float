# Spec — "Floating Alone in Space" Immersive Environment (Apple Vision Pro)

**Target platform:** visionOS 27 (developer beta) — see §10 for beta caveats
**App type:** Full Immersive Space (`.full`), single-user, no passthrough
**Core intent:** User floats alone in deep space. Stars and nebula fully surround them. Genuinely 3D (parallax + stereo depth, never flat). High resolution. Animated (nebula color drift, comets / astronomical phenomena). Optional **hero celestial bodies** — planets, stars (including real solar-system bodies), and **asteroid fields** — placed at a fixed viewing distance. A **double-pinch** gesture reveals a control panel with (a) an animation-speed slider and (b) a "new environment" action that triggers a **Star Wars-style hyperspace jump** into a freshly generated environment. Any location can be **saved and returned to exactly** (§7e).
**Non-goals (explicitly cut):** astronomical accuracy, free navigation/locomotion (the hyperspace jump is a scripted transition, not user-piloted flight), **surface-level planetary approach / continental LOD** (bodies are viewed at a fixed hero distance), multiplayer, real star catalogs (optional flavor only).

---

## 1. Bottom line

- Feasible for a solo experienced dev. **Genuinely-3D animated prototype: ~1.5–2 weeks. Full polished build with every feature below: ~6.5–9 weeks solo** (see §12 for the breakdown). The core "float in a 3D starfield" is a few days; the range is driven by the interaction, physics, and content features layered on top.
- The only *hard* requirement is "must feel 3D." Everything else (surround, resolution, animation, hidden slider) is well-trodden on visionOS.
- visionOS 27 beta specifically de-risks the nebula: **native Gaussian splat rendering** gives real volumetric depth instead of the flat-billboard workarounds you'd fight on 26.
- Biggest real risks are **fill-rate/overdraw performance** and **comfort**, not API capability. Both are managed by design choices in this spec, not luck.
- **Sharpest single risk: the hyperspace jump.** A forward star-rush is exactly the optic-flow pattern that triggers motion discomfort in a headset. It is buildable and can be made comfortable, but it needs deliberate mitigation (§7b) — it is the one feature most likely to make someone take the headset off.

---

## 2. Why a single skybox fails (the central design constraint)

- Vision Pro is 6DoF and stereoscopic. Depth perception comes from two cues: **stereo disparity** (each eye sees a slightly different image — strong for objects roughly 1–50 m out) and **motion parallax** (near objects shift against far ones when the head translates — leaning, turning).
- A single equirectangular sphere at "infinity" has **zero disparity and zero parallax** → the brain reads it as a painted dome. That is the "flat" failure you called out.
- **Therefore the environment must place real geometry at multiple finite, varied depths.** Depth is produced by the *distribution* of elements in a volume, not by any one texture. This is the architecture in §3.

---

## 3. Architecture — layered depth shells

Concentric volumes, near → far. Each shell contributes a different depth cue. Distances are starting points to tune, not fixed.

```
        user (0,0,0), stationary
   ┌──────────────────────────────────────────────┐
   │  L4  NEAR PHENOMENA        2–30 m             │  comets, meteors, drifting dust
   │      (moving, trailed, occluding)             │  → strongest 3D read (motion + stereo)
   │   ┌──────────────────────────────────────┐   │
   │   │  L3  STAR VOLUME     ~2–200 m         │   │  thousands of points in a 3D shell
   │   │      (parallax workhorse)             │   │  → near stars parallax vs far stars
   │   │   ┌──────────────────────────────┐    │   │
   │   │   │  L2  NEBULA VOLUME 15–120 m   │    │   │  Gaussian splats (primary, v27)
   │   │   │      (volumetric, animated)   │    │   │  → real volumetric depth + color drift
   │   │   │   ┌──────────────────────┐    │    │   │
   │   │   │   │ L1 FAR BACKDROP      │    │    │   │  hi-res equirectangular Milky Way
   │   │   │   │    ~900–1000 m       │    │    │   │  → fills FOV; effectively at infinity
   │   │   │   └──────────────────────┘    │    │   │
   │   │   └──────────────────────────────┘    │   │
   │   └──────────────────────────────────────┘   │
   └──────────────────────────────────────────────┘
```

| Layer | Purpose | Primary depth cue | Implementation (v27) | Motion |
|-------|---------|-------------------|----------------------|--------|
| **L1 Far backdrop** | Fill the whole FOV so there are no gaps; base "stars everywhere" | none (it's the infinity plate) | Inward sphere, `UnlitMaterial`, hi-res equirectangular (§4) | Static or ultra-slow yaw |
| **L2 Nebula volume** | The signature look; the thing that must feel volumetric | Volumetric self-parallax + stereo | **Gaussian splats** (native RealityKit v27), fallback: additive soft particle clouds + a few billboard sheets | Color/emissive drift; very slow drift |
| **L3 Star volume** | The main 3D seller: parallax of near vs far stars | Parallax + stereo | Instanced points via `LowLevelMesh`, OR fixed `ParticleEmitterComponent` field | Optional slow global rotation; twinkle |
| **L4 Near phenomena** | Life and "wow"; unmistakably 3D because they move through the volume | Motion parallax + stereo + occlusion | Spawner system → entities with particle trails | Comets/meteors cross; dust drifts |

Design rules that keep it from going flat:
- **Never cluster everything at one radius.** Spread L3 across ~2–200 m with a density falloff.
- **Keep meaningful structure inside ~50 m** so stereo disparity registers.
- **User camera stays fixed at origin.** All apparent motion is objects moving, not the viewer (comfort — §9).
- **Hero celestial bodies (§7c), when present,** sit in the mid/far field (~40–150 m) as discrete lit objects; keep L3 stars and L4 dust in front of them so a body never reads as flat wallpaper.
- **Asteroid fields (§7d) are the premium depth element** — solid rocks at near/mid range deliver strong stereo, parallax, and occlusion at once. Lean on them when an environment needs to feel unmistakably 3D.

---

## 4. Resolution strategy ("as high-res as we can")

"Highest resolution" is **memory- and fill-rate-bound, not desire-bound.** Define a budget rather than chasing a number.

- **L1 backdrop:** equirectangular, target **8K–16K (8192×4096 → 16384×8192)**. 16K equirect is large in memory — mitigate with:
  - **Cubemap** (6 faces) instead of one equirect → better texel distribution, avoids pole pinch, easier to keep each face high-res.
  - **ASTC compression** (e.g. ASTC 6×6/8×8) to cut VRAM sharply with minimal visible loss on diffuse star fields.
- **L2 nebula:** if splats, resolution = splat count + quality, not a texture. Budget splat count against frame time; start modest and scale up while watching the frame profiler.
- **Foveation** is automatic on Vision Pro — peripheral detail is cheaper than it looks, so spend the budget on what's near center.
- **Perf target: hold 90 fps** (dropped frames in an immersive space read as discomfort, not just jank). Resolution ceiling is "the most that still holds 90 fps on device," found empirically.

**Assumption flagged:** the M-series Vision Pro can hold 90 fps with a 16K cubemap + moderate splat nebula + a few thousand instanced stars + capped particle trails. Plausible but **unverified — must be validated on-device early.** Treat the res number as a tuning outcome, not a spec guarantee.

---

## 5. Animation system

Single global clock so everything speeds/slows together from one control.

- **`TimeScale: Float`** — global multiplier, default `1.0`, range `0.0`–`~10.0` (0 = full freeze). Owned by an `AnimationClock` component/singleton.
- A RealityKit **`System`** runs each frame: `simTime += context.deltaTime * TimeScale`, then drives all animated parameters from `simTime`. One clock → the hidden slider (§7) controls the entire scene.
- **Determinism (foundational):** every animated value is a pure function of `simTime` and the seed, using a seeded PRNG with no wall-clock and no unseeded randomness. This is what makes saved locations (§7e) reproducible, and it's cheap to design in from the start but painful to retrofit.

> **Determinism vs. realism — no conflict for this app.** Reproducibility is orthogonal to fidelity. A seeded PRNG samples the same distributions as an unseeded one; realism comes from *which* distributions and materials you use (real stellar color/brightness populations, power-law asteroid sizes, PBR lighting, real NASA textures, splat nebulae) — the seed constrains none of it. The only motion style that would fight the "pure function of time" rule is **emergent physics** — n-body gravity, collisions/fragmentation, evolving turbulence — which accumulates chaotic state and can't be evaluated at an arbitrary instant. Most of this app's motion (orbits, rotation, gentle drift, noise-driven color) is analytic in time, so it stays fully deterministic *and* fully realistic with no tradeoff. Emergent physics is used in exactly one bounded place — asteroid impacts and fragmentation (§7d) — under a two-layer model: the deterministic layer (stars, nebula, bodies, the asteroid field's initial state) stays a pure function of (seed, time) and reproduces exactly, while the physics layer runs free. Saved locations restore the *initial conditions* of an impact scenario, not its evolved outcome, so the same dramatic setup recurs and the shatter varies each replay (§7e). This keeps saves tiny and skips any need for checkpointed deterministic physics.

Animated elements:

| Element | What animates | How |
|---------|---------------|-----|
| Nebula color drift | Hue / emissive / density shift | ShaderGraph material params on splats (or particle color ramp) keyed off `simTime`; slow LFO over minutes |
| Star twinkle | Per-star brightness jitter | Cheap noise in the star material/shader; subtle |
| Global drift | Very slow yaw of L2/L3 | Small angular velocity × `TimeScale` |
| Comets / meteors | Spawn + travel + fade | Spawner system (§6) |
| Dust motes | Gentle parallax drift | Low-rate particle field |

Note (v27): SwiftUI can animate RealityKit entities/components directly — usable for UI transitions (slider fade-in), but the scene clock should stay in the ECS `System` for frame-rate-independent control.

---

## 6. Comets & astronomical phenomena (L4)

- **Spawner system**: on an interval scaled by `TimeScale`, instantiate a phenomenon entity, animate it across the volume, despawn on exit/fade. Pool/reuse entities to avoid allocation hitches.
- **Comet:** bright head + `ParticleEmitterComponent` trail (elongated, additive, slight color gradient). Crosses over seconds–minutes depending on `TimeScale`.
- **Meteor / shooting star:** fast, short-lived streak; higher spawn rate than comets.
- **Optional flavor:** slow pulsar blink, a distant "supernova" bloom (one-shot emissive flash + expanding shell), aurora-like curtains (v27 ships a Thórsmörk env with aurora — reference for look, not reusable asset).
- **Projective lighting (v27):** point/spot lights with projected textures can throw moving colored light onto nearby dust/nebula as a comet passes — cheap way to make phenomena feel like they interact with the space.
- Keep counts capped and phenomena mostly beyond ~5 m to protect comfort and fill rate.

---

## 7. Double-pinch reveal + control panel

Three parts: **detect double-pinch → reveal panel → bind controls.**

- **Hand tracking:** ARKit `HandTrackingProvider`, **90 Hz on v26+**. Requires the full ImmersiveSpace and a one-time hand-tracking authorization — both already true here.
- **Reveal gesture = double pinch** (thumb+index "double click"):
  - Detect a pinch as thumb-tip↔index-tip distance crossing below a threshold, then releasing above it. A **double pinch = two pinch/release cycles inside ~350–450 ms**, same hand.
  - Tune a hysteresis gap (distinct enter/exit thresholds) so one slow pinch isn't read as two.
  - **Conflict flag (real):** the single pinch is visionOS's *primary system selection gesture* (the "tap"). A custom double-pinch listener can fight with system input, and the first pinch of your double may register as a stray system tap on whatever the eyes are resting on. Mitigations: only arm the detector when gaze is **not** on an interactive attachment; consider requiring the pinch be held slightly, or use a dedicated `SpatialEventGesture` / `GestureComponent` (v26+) rather than raw joints. **Prototype this first — it's the riskiest interaction detail.**
- **Panel UI:** SwiftUI in a `ViewAttachmentComponent` (v26+), placed at a comfortable fixed distance near where the pinch happened (not hand-anchored, so it holds still while you reach for it). `PresentationComponent` for fade in/out. Contents:
  - **Speed slider** → writes `TimeScale`. Discrete "freeze" at 0; subtle label ("0.5× … 1× … 5×"). 
  - **"New Environment" action** → triggers the hyperspace transition (§7b) into a freshly generated environment (§7a). Optionally a small preset picker (nebula palette / density) if you want directed variety rather than pure random.
- **Dismiss:** another double-pinch, a close control, or auto-hide after a few seconds idle.

---

## 7a. Environments as regenerable presets

To "rebuild into something different," an environment must be a **parameter set**, not hardcoded scene-building.

- **`EnvironmentConfig`**: seed + nebula backend/palette + nebula density + star density/color mix + backdrop choice + phenomena rates + celestial body / asteroid-field selection (§7c–§7d). One struct fully describes a look.
- **Generation** consumes a config and (re)builds L1–L4 deterministically from the seed. Same seed → same universe (useful for "take me back to that one").
- **"Different" = new config.** Either fully random (roll a new seed + random palette) or drawn from a curated preset list (e.g. "violet nebula," "sparse deep field," "dense star nursery"). *Open decision, §11.*
- Build the **new** environment **behind the current one during the jump** (§7b), then swap — so there's no loading gap mid-transition. Pool/reuse buffers to avoid a hitch when the old one tears down.

---

## 7b. Hyperspace transition (the environment swap)

Star Wars-style: stars stretch into radial streaks, rush past, then settle into the new environment. This is the **highest comfort-risk feature in the app** — spec it defensively.

Sequence (target ~1.5–3 s total):
1. **Anticipation (0.2–0.4 s):** slight settle / dim; optional audio cue. Signals intent so the motion isn't a surprise (surprise worsens discomfort).
2. **Stretch + rush (0.6–1.5 s):** L3 star points elongate into streaks along the radial-from-forward direction and accelerate outward past the viewer (velocity-aligned scaling on the instanced points, or a dedicated streak particle pass). Old L1/L2 fade down. This is faked forward motion — **the camera itself does not translate** (moving the camera is worse for comfort than moving the field).
3. **Whiteout / peak (~0.1–0.3 s):** brief bloom/flash to mask the swap of L1/L2 assets.
4. **Arrival (0.4–0.8 s):** streaks decelerate and recontract into the **new** environment's star volume; new nebula/backdrop fade in.

**Comfort mitigations (treat as required, not optional):**
- Keep it **short**. Longer = more accumulated vection = more nausea.
- **Peripheral vignette/dim during the rush** — reduces optic flow in the periphery, the main nausea driver. This single mitigation matters most.
- **User-initiated only** (they chose it), which is inherently more tolerable than imposed motion.
- Provide a **"comfort" intensity setting**: full effect ↔ reduced (shorter, dimmer, less streak speed) ↔ "cut" (simple crossfade, no rush) for anyone the effect bothers. *Open decision on defaults, §11.*
- No real acceleration curve that implies sustained g-force; ease in and out.

**Feasibility:** straightforward to build — it's animated scaling/velocity on existing L3 geometry plus a timed asset swap. The engineering is easy; **getting it to feel exciting without being sickening is the tuning cost**, and it must be validated on-device with a couple of other people, not just you.

---

## 7c. Celestial bodies — planets & stars as hero objects

**Framing principle (matches your instinct):** a body sits at a fixed "hero" distance — large enough to enjoy color, rings, and atmosphere, far enough that one texture carries it with no surface LOD, no continental streaming, no approach detail. The vantage stays fixed near the body; the hyperspace jump is what changes which body you're beside.

**Planet body:**
- Sphere + high-res equirectangular planetary map (8K–16K). Single texture, no LOD tree — because the framing distance is fixed.
- Directional light from the local star gives a day/night terminator and crescent. Nearly free, and the terminator is one of the strongest shape/depth cues available.
- Atmosphere limb glow: a slightly larger transparent shell with a fresnel rim shader. Cheap, and it reads unmistakably as a planet.
- Optional cloud shell: a second transparent sphere rotating at a different rate for parallax and motion. For gas giants, animate banding with scrolling shader noise.
- Rings (Saturn-type), **two-tier so they resolve up close** rather than reading as a painted stripe:
  - *Bulk band:* a flat textured annulus with transparency and radial banding (Cassini-style gaps) carries the ring at a glance and at distance — physically honest, since most real ring particles are far too small to resolve individually anyway.
  - *Resolvable debris (when close):* overlay a belt of discrete instanced rocks in the ring plane, LOD-gated to the arc nearest the viewer. Up close, the near ring breaks into individual tumbling rocks and debris with real thickness and parallax; farther arcs blend back into the textured band. This reuses the §7d asteroid instancing, so the added cost is small.
  - Ring particles orbit in-plane (slow, `TimeScale`-driven, slightly faster on inner radii for flavor), lit by the star. Add ring-on-planet and planet-on-ring shadows to splurge.
  - If an environment seats the vantage inside or near the ring plane, the near debris follows the §7d safety rules (no looming, no approach toward the head).
- Optional night-side city lights (emissive map, Earth).
- Very slow rotation tied to `TimeScale`.

**Star / Sun up close:**
- Emissive sphere with animated granulation (flowing noise), limb darkening, and sunspots; corona as additive glow or sprites; occasional prominences and flares as particle arcs; bloom on top.
- v27 projective lighting can throw flickering colored light onto nearby dust and nebula.
- **Comfort / eye-strain flag (blunt):** a bright star filling the near field of an HMD is fatiguing and can be actively uncomfortable. Required constraints: cap peak luminance, hold angular size moderate so it never fills the whole FOV, keep bloom from washing out the rest of the scene, and keep the viewing distance respectful. "Next to the Sun" should mean the Sun is a dominant presence in view, well short of pressed against your face.

**Depth behavior (nuance worth knowing):**
- A body big enough to read as a whole planet naturally sits beyond ~20 m, where stereo disparity has faded. That matches reality — planets in the sky carry no stereo depth. Their dimensionality comes from lighting, the terminator, rotation, atmosphere, and the parallax of nearer stars and dust drifting in front of them. So bodies keep the "never flat" goal intact as long as the L3 star volume and L4 dust stay in the foreground.

**Real solar-system option:**
- NASA / JPL / USGS publish public-domain equirectangular maps for the Sun, every planet, and major moons (Earth Blue Marble and Black Marble, Mars, Jupiter, Saturn with rings, and more). Strong fit for a "Sol System" curated preset.
- Flag: verify each asset's license and attribution individually, though NASA imagery is generally public domain and free to use.
- "Sol System" preset = a curated `EnvironmentConfig` placing a recognizable real body (correct texture, color, rings) at hero distance. Recognizable scenery only — not to scale, not accurate orbital positions (that stays a non-goal).

**Integration with environments (§7a):**
- Body becomes a config field: none / procedural planet (random palette, rings on-off, atmosphere tint) / named real body / the star. One jump can land you beside a ringed gas giant, the next near the Sun.

**Movement decision (flagged — see §11 #10):**
- Assumption: the vantage near a body is fixed per environment, and the jump moves you between setups. This is deliberate — piloting toward a body would reintroduce exactly the surface-detail/LOD problem you want to avoid. Approaching or orbiting bodies is a materially larger build (LOD, texture streaming, collision) and should be scoped separately if you want it.

---

## 7d. Asteroid fields

**Concept:** the user sits inside a volume of drifting rocks at varied distances. Beyond the look, this is the strongest depth element in the whole design — solid objects at near and mid range give stereo disparity, parallax on head movement, and mutual occlusion together, so it does the most to keep the scene from ever feeling flat.

**Anti-anxiety motion (your constraint — a hard construction rule, not a tuning preference):**
- **Safety bubble:** a clear exclusion sphere (~2–3 m radius) around the viewpoint. No asteroid trajectory ever enters it.
- **Guaranteed by construction:** spawn each asteroid on a straight lateral drift whose closest-approach distance to the origin is chosen up front to exceed the safety radius. Despawn at the far edge, respawn at the entry edge — a slow conveyor of rocks that pass to the side. The user's safety bubble holds here with no runtime checks; the optional impact layer below adds asteroid-on-asteroid physics but still honors that bubble.
- **No looming:** velocity vectors run lateral/tangential and are never aimed at the head. Nothing grows rapidly in the near field — fast optical looming is the specific cue that triggers a flinch/threat response, so the design forbids it outright.
- **Gentle and predictable:** slow drift, no sudden direction changes near the user; larger rocks kept farther out, only small ones permitted to pass closer (still outside the bubble).
- **Tumble is welcome:** each asteroid spins slowly on its own axis. Axial spin adds life and reads as natural; only translational approach toward the head causes anxiety, and that's the part ruled out above.

**Rendering (cheap at scale):**
- Instanced rocky meshes — a handful of base shapes with per-instance scale, rotation, and axis variation, plus a rocky albedo + normal map. Instancing (a v26+ optimization) handles hundreds of rocks cheaply.
- Lit by the local star (directional) so each rock shows a lit side and a shadowed side — the same terminator logic as planets, reinforcing depth.
- Optional: a few large "hero" asteroids farther out for scale, with fine dust particles (L4) drifting between them.
- All motion scaled by `TimeScale`; the slider at 0 halts the field.
- **Reused elsewhere:** this same instanced-rock system drives the resolvable planet-ring debris in §7c — build it once, use it for both.

**Environment integration (§7a):**
- "Asteroid field" becomes a scene option, standalone or combined — a field drifting in front of a ringed gas giant, or backlit by a nearby star.

**Emergent impacts & fragmentation (optional dynamic layer):**
- This is deliberately the one place the app uses emergent, chaotic simulation (§5). **Accepted model:** the starting conditions are seeded and reproducible (a saved spot restores the same scenario — e.g. the same two rocks on a crossing course), and the evolution runs free, so each replay fragments differently. Saved locations restore the sim's *initial* conditions, not its evolved state (§7e).
- **Physics:** asteroids inside an "active zone" near the vantage become dynamic rigid bodies (RealityKit `PhysicsBodyComponent` + `CollisionComponent`). Rocks on seeded crossing trajectories collide naturally; distant rocks stay on cheap kinematic drift and promote to full physics only when they enter the active zone.
- **Fragmentation via pre-fracture (recommended):** author each asteroid offline with a precomputed Voronoi-shatter set of fragments. On an impact above an energy threshold, swap the intact rock for its fragment pieces, inheriting the parent velocity plus the collision impulse, and emit a dust/spark burst (L4 particles) at the contact point. Cheap at runtime, convincing, and it avoids real-time mesh fracture.
- **Perf discipline:** physics only in the active zone; cap simultaneous shatter events; limit fragments per break; despawn small fragments on a timer. Hundreds of colliding bodies with fracture is the heaviest thing in the app — budget it and validate on-device.
- **Comfort reconciliation (hard rule):** fragmentation wants to throw debris everywhere, including toward the head — which fights §9's safety bubble. The bubble wins, and **fade is the primary treatment**: a head-bound fragment is allowed to begin its arc (so you see the impact and the first moment of the break), then smoothly dissolves before it reaches the bubble. Fading reads far more naturally than debris ricocheting off an invisible shell, so deflection is only a secondary fallback for edge cases. Impact events stay out in the field. A small, deliberate realism compromise near the user in exchange for an absolute no-anxiety guarantee.

---

## 7e. Saved locations ("return to this spot")

**The key realization:** recording every star position and motion path is unnecessary. Because each environment is generated deterministically from a seed (§7a) and animated by a single clock (§5), the whole universe — star layout, asteroid field, nebula, bodies, and where each one sits at a given instant — reproduces from a tiny save. A saved location is a few hundred bytes plus a thumbnail, not gigabytes of recorded positions.

**What a save captures:**
- The `EnvironmentConfig` (seed + all generation params).
- The animation clock value `simTime` at capture, so bodies, background stars, and nebula restore to the exact moment. (The asteroid-impact layer restores its seeded initial conditions and re-simulates — §7d — so that scenario replays rather than freezing at the saved instant.)
- `TimeScale` at capture (restore paused or at speed).
- A **rendered thumbnail image** — the literal "screenshot," used as the visual label in the gallery.
- A generator-version tag (see caveats).

**Restore:**
- Regenerate the scene from the seed, set `simTime` and `TimeScale`, and the identical universe reappears. Arrive via the hyperspace jump (§7b) for continuity, or a gentle fade.

**Design requirement this imposes (same rule as §5):**
- Generation and animation must be **pure functions of (seed, simTime)** — a seeded PRNG (Xoshiro / SplitMix64 seeded from the config seed), no wall-clock, no unseeded randomness. Foundational, not a late add.

**Caveats (flagged):**
- **Asteroid impacts (by design, not a limitation):** the impact/fragmentation layer (§7d) is emergent and intentionally non-reproducible. A saved spot restores the scenario's seeded initial conditions (same setup), and the collision outcome varies each replay — exactly the behavior you chose.
- **Comets / meteors:** reproduce exactly only if their spawner is also a deterministic function of (seed, simTime). Recommended: make it deterministic so a returned spot looks truly identical. If that proves fiddly, the stable structure still matches and only passing "sky traffic" differs. *Open decision, §11 #13.*
- **Generator versioning:** if the generation algorithm changes in a future app version, an old seed could regenerate differently. Store a generator-version tag with each save and keep old generators available (or migrate), so saves don't silently drift after an update.
- **Splat nebula:** an authored (non-procedural) splat nebula is a fixed asset, so it reproduces trivially — just reference the asset + palette params. Only procedurally generated nebula relies on seed determinism.

**UI:**
- "Save this spot" on the double-pinch panel; a "Places" gallery of thumbnails to browse and jump back to. Persist with SwiftData or Codable JSON + image files.

---

## 7f. Direct hand interaction — flicking asteroids

**How hard: moderate, ~1–2 days — most of the pieces already exist.** Hand tracking is in for the double-pinch panel (§7), and nearby asteroids are already physics bodies in the active zone (§7d). A flick is just mapping hand motion to an impulse on a rock you touch.

**Approach (for a real "flick," not a grab):**
- Attach a small kinematic collider to the fingertip/hand from the hand-tracking joints. When it intersects an asteroid's collision shape, transfer momentum from the hand collider's estimated velocity into an impulse on the rock, so it tumbles away along your flick (RealityKit physics + a velocity-smoothed hand collider).
- Alternative: the v26+ Manipulation / grab-and-release APIs give a pinch-grab-throw — reliable, but it reads as "throw" rather than "flick." Use the fingertip-collider route for the batting-a-rock feel.
- **Mass-scaled impulse:** a flick spins a small rock off noticeably but barely nudges a large one — sells the sense of mass.

**Reachability vs. the safety bubble (the reconciliation):**
- Tension: the ambient field is excluded from a ~2–3 m bubble, but arm's reach is ~0.7 m — so ambient rocks are never touchable, by design (no unbidden approach).
- Resolution: a **small set of "tame" interactable rocks** may drift slowly at reachable distance (~0.5–0.8 m). The bubble exists to stop *unbidden, fast* approach that startles; a slow rock you can see and choose to engage is consented interaction and stays comfortable. Ambient hazard rocks and tame interactable rocks are separate populations.
- *Open decision (§11 #14):* how a rock becomes reachable — always keep a few tame ones nearby, or a "beckon"/summon gesture that draws one into reach on demand.

**Comfort & determinism:**
- A flick sends a rock *outward*, away from you, so it never looms. If physics later rebounds one back toward the head, the §9 bubble override (fade, then deflect) still applies.
- Flicking is user input, so it lives in the free-running layer (§5); saved locations restore initial conditions and don't record pokes — consistent with §7e.
- Hand-velocity estimation needs smoothing (fast flicks stress 90 Hz tracking) — minor tuning, flagged.

---

## 8. Data / assets

| Asset | Source options | Notes / flag |
|-------|----------------|--------------|
| L1 equirectangular backdrop | ESO Milky Way panorama (S. Brunier), NASA/ESA star maps; or procedural (generate an 8K+ equirect PNG in Python) | **License + resolution must be verified before shipping — not yet checked.** Procedural avoids licensing entirely. |
| L2 nebula splats | Author in a splat tool / convert from volumetric renders; or procedurally author cloud fields | Splat authoring pipeline is the least mature part; budget learning time |
| L3 star distribution | Procedural random in a 3D shell (fine for "looks good"); optional seed from Gaia/Hipparcos bright stars for plausible clustering | Procedural recommended for v1 |
| L4 phenomena | Procedural (particles + shaders) | No external assets needed |
| Planetary maps (§7c) | NASA/JPL/USGS public-domain equirectangular maps; or procedural | Per-asset license/attribution to confirm; NASA generally public domain |
| Star/Sun surface (§7c) | Procedural (granulation/corona shaders); NASA SDO imagery for reference | Procedural recommended; keep luminance capped |
| Asteroids (§7d) | A few base rocky meshes + albedo/normal maps; procedural or free CC0 rock assets | Instanced; verify license on any downloaded mesh |

---

## 9. Comfort (hard constraint, not polish)

- **Camera never moves.** Only distant objects move, slowly. Self-motion illusion in a headset causes discomfort fast.
- Keep large-scale motion (drift, rotation) **very slow**; keep fast motion (meteors) **small and peripheral**.
- Deep-black background between stars; avoid full-field brightness pulses.
- No sudden large occluders swooping close to the face.
- **The hyperspace jump (§7b) is the exception that needs its own budget.** It deliberately breaks the "slow motion only" rule, so it must carry every mitigation in §7b (short duration, peripheral vignette, user-initiated, comfort intensity setting). Test it on other people, not just yourself — tolerance to vection varies widely.
- **A close bright star (§7c) is an eye-strain source,** separate from motion comfort. Cap peak luminance, keep it from filling the FOV, and keep bloom contained. Sustained bright HDR content in the near field fatigues the eyes even when it never moves.
- **Asteroid fields (§7d) carry a built-in comfort guarantee:** the safety bubble and lateral-only drift ensure nothing approaches the head. This is enforced at spawn time (trajectory closest-approach > bubble radius), so it holds by construction rather than depending on per-frame checks.
- **Emergent asteroid impacts (§7d) do not get to override the safety bubble.** A head-bound fragment is allowed to begin its arc (you see the impact start) and then **fades out** just before the exclusion zone; deflection is the fallback. Impact events are kept out in the field. Chaotic physics is allowed, but never at the cost of something reaching the user's face.

---

## 10. visionOS 27 beta caveats

- **Beta API churn:** signatures for the newest features (native Gaussian splats, projective lighting) can change between betas — expect rework.
- **No App Store shipping until 27 is stable** (this fall). Fine for a personal/dev build now; note it if distribution is ever a goal.
- **Fallback path:** if a splat feature is unstable, L2 degrades gracefully to additive soft-particle clouds + billboard sheets on the same clock — the rest of the architecture is unaffected. Design L2 as a **swappable module** behind a protocol so the nebula backend can change without touching L1/L3/L4.

---

## 11. Open decisions (for you to resolve before build)

1. ~~Reveal gesture~~ — **RESOLVED: double pinch** (§7). Open sub-question: fall back to a simpler gesture if double-pinch fights system input too much in testing?
2. **Nebula backend commitment:** commit to Gaussian splats now, or build the particle fallback first and add splats once its API settles?
3. **Backdrop source:** real panorama (needs license check) vs. procedural generation?
4. **Star distribution:** pure procedural vs. real-catalog-seeded?
5. **`TimeScale` range + freeze:** confirm 0–10× with a 0 freeze, or different bounds?
6. **Resolution budget:** set a target device frame-time budget so §4 has a concrete ceiling to tune against.
7. **"New environment" variety:** fully random (new seed + random palette) vs. a curated preset list? — affects whether results are always pleasing or occasionally ugly.
8. **Hyperspace default intensity:** full effect by default, or ship "reduced" as the default and let the user opt up? — conservative default protects first-run comfort.
9. ~~Environment persistence~~ — **RESOLVED: reproducible.** Saved locations restore exactly from seed + `simTime` + thumbnail (§7e).
10. ~~Movement model~~ — **RESOLVED: fixed vantage per environment; hyperspace jumps reposition you between setups. No free flight toward bodies.** (Keeps bodies cheap and dodges surface LOD.)
11. **Star size/brightness defaults:** set the default angular size and luminance cap for a "next to the Sun" scene so it's impressive without being fatiguing.
12. **Ring vantage:** default to viewing a ringed planet from above/outside the ring plane (simplest, always comfortable), or allow environments that seat you within the ring plane among resolvable debris (more dramatic, needs §7d safe-drift applied to the near ring particles)?
13. **Transient-phenomena determinism:** — asteroid impacts **RESOLVED** (seeded start, free-running evolution; §7d). Still open for **comets/meteors**: make their spawner deterministic so saved spots reproduce exact "sky traffic," or accept that passing phenomena vary on return?
14. **Reachable rocks for flicking (§7f):** always keep a few slow "tame" asteroids within arm's reach, or draw one in on demand via a "beckon"/summon gesture? — affects discoverability and how cluttered the near field feels.

---

## 12. Effort estimate (solo, experienced visionOS dev)

| Work item | Rough range |
|-----------|-------------|
| Project scaffold + Full Immersive Space + L1 backdrop | 0.5 day |
| L3 star volume (instanced, parallax tuned) | 1–2 days |
| L2 nebula (splat path; +buffer if learning splat authoring) | 3–6 days |
| L4 comets/meteors + trails + spawner | 1–2 days |
| Global `TimeScale` animation system | 0.5–1 day |
| Double-pinch detection + control panel (incl. system-input conflict handling) | 1.5–3 days |
| Environment config + regeneration system (§7a) | 1–2 days |
| Hyperspace transition + comfort tuning (§7b) | 2–4 days |
| Planet body module (texture / atmosphere / two-tier rings / star-lighting / rotation) | 1.5–3.5 days |
| Star/Sun module (emissive surface / corona / flares + luminance caps) | 1.5–3 days |
| Asteroid field module (instanced rocks + safe-drift spawner) | 1–2 days |
| Saved locations (capture config+time+thumbnail, gallery, restore) | 1–2 days |
| Asteroid impact + fragmentation physics (pre-fracture, active-zone sim, debris, bubble deflection) | 2–4 days |
| Flick interaction (fingertip collider → mass-scaled impulse, tame rocks) | 1–2 days |
| Integration, on-device perf/comfort tuning | 2–3 days |
| **Total (polished)** | **~6.5–9 weeks** |
| **Genuinely-3D animated prototype (rough L2, one phenomenon, working panel, basic jump, one planet)** | **~1.5–2 weeks** |

Biggest schedule uncertainties, in order: **Gaussian splat authoring/pipeline** (newest, least-documented), **double-pinch vs. system-pinch conflict** (interaction risk), **hyperspace comfort tuning** (subjective, needs multi-person testing), and **perf to hold 90 fps** at high resolution.
