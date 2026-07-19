# Float — Build Plan

Risk-ordered milestones for building the spec in `../starfield_immersive_spec.md`.
Core principle: prove the scary things first, test on-device and on other people early, and keep one clock and a deterministic core the whole way.

## Guiding rules
- **On-device every milestone.** The simulator misrepresents stereo depth, comfort, and fill rate — the three things that make or break this app.
- **One clock (§5).** Nothing animates off wall-clock; everything reads `AnimationClock.simTime`.
- **Deterministic core (§5/§7e).** Generation and non-physics animation use `SeededRandom` only.
- **Comfort is a gate (§9), not a polish pass.** A milestone that regresses comfort is not "done."
- **Perf budget (§4).** Hold 90 fps on device; every layer carries a cost ceiling.

## Risk register (this is what drives the ordering)
1. **Depth actually reads as 3D** (§2/§3) — make-or-break → front-loaded to Milestone 1.
2. **Double-pinch vs. system-pinch conflict** (§7) — interaction risk → Milestone 3.
3. **Hyperspace vection/comfort** (§7b) — most likely to make someone remove the headset → Milestone 4, multi-person test.
4. **Physics + fragmentation perf** (§7d) — heaviest system → Milestone 7, perf-gated.
5. **Gaussian splat pipeline maturity** (§10) — newest API → isolated behind the NebulaBackend protocol from Milestone 2 so it can't block anything else.

## Milestones

### M0 — Bootstrap (~0.5 day)
- `xcodegen generate`; app runs; opens an empty Full Immersive Space; hand-tracking auth prompt fires.
- **Exit:** builds and deploys to the device; enter/exit immersion works.

### M1 — Prove depth (~2–3 days) — do this before anything pretty
- L1 backdrop + L3 star volume only. No nebula, no animation.
- Distribute stars across ~2–200 m with a density falloff; tune until near/far parallax and stereo clearly read on-device.
- **Exit (hard gate):** standing in it feels genuinely 3D when you lean and turn. If it doesn't, stop and fix the distribution before going further — every later feature rides on this.

### M2 — Clock + nebula + phenomena (~3–6 days)
- AnimationClock system online; star twinkle and drift read from `simTime`.
- NebulaVolume behind the backend protocol: start with the particle fallback (reliable), stub the splat path.
- L4 comet/meteor spawner.
- **Exit:** a living, drifting scene at TimeScale 1; nebula shows volumetric depth (not a flat wall); 90 fps holds.

### M3 — Interaction spine (~2–3 days) — de-risk the gesture
- Double-pinch detector + control-panel attachment + TimeScale slider.
- Spend the budget on pinch-vs-system-tap disambiguation: gaze-off-UI arming, hysteresis, or a dedicated SpatialEventGesture.
- **Exit:** panel opens/closes reliably; slider scales all motion including freeze at 0; false-trigger rate is low.

### M4 — Environments + hyperspace (~2–4 days) — comfort gate
- EnvironmentConfig + generator; "New Environment" rolls a config.
- Hyperspace transition with all §7b mitigations; a comfort-intensity setting exists from day one.
- **Exit:** a multi-person test (not just you) reports the jump as exciting rather than sickening at the default intensity. Ship "reduced" as the default if there's any doubt (§11 #8).

### M5 — Celestial bodies (~3–6 days)
- Planet (texture + directional-light terminator + atmosphere + optional clouds); two-tier rings; star/sun with luminance caps.
- Sol System preset wiring (real NASA maps — verify licenses first).
- **Exit:** a ringed planet and a "next to the Sun" scene, both comfortable; the ring resolves into individual debris up close.

### M6 — Asteroid field + flick (~2–4 days)
- Safe-drift instanced field (bubble guaranteed at spawn time); tame reachable rocks; fingertip-collider flick with mass-scaled impulse.
- **Exit:** a dense field reads as strongly 3D; nothing ever approaches the head; flicking a tame rock feels right.

### M7 — Emergent impacts + fragmentation (~2–4 days) — perf gate
- Active-zone rigid-body promotion; pre-fractured shatter on impact; dust bursts.
- Safety override: head-bound fragments fade before the bubble.
- **Exit:** visible impacts and fragmentation with 90 fps held under worst case; no fragment ever reaches the face.

### M8 — Saved locations (~1–2 days)
- Capture config + `simTime` + `timeScale` + thumbnail; Places gallery; restore via the jump.
- **Exit:** save a spot, jump away, return — the deterministic layer matches exactly, and the impact scenario replays from its seeded start.

### M9 — Polish + hardening (~2–3 days)
- Perf hardening to the resolution budget; comfort settings surfaced; generator-version guard; splat backend swapped in if its API has stabilized.
- **Exit:** sustained 90 fps across environments; comfort options complete; no determinism drift on save/restore.

## Dependency order
```
M0 → M1 → M2 → M3 → M4 → { M5 , M6 } → M7 → M8 → M9
```
M5 and M6 can run in parallel after M4. M7 depends on M6. M8 depends on M4 + M6.

## On-device validation at each gate
- Stereo/parallax reads (M1); 90 fps (M2 / M7 / M9); gesture false-trigger rate (M3); vection comfort with 2–3 people (M4 / M7); safety bubble never breached (M6 / M7); determinism on restore (M8).

## Open decisions to close as you reach them
- Nebula backend commit (§11 #2) — at M2.
- TimeScale range + freeze (§11 #5) — at M3.
- Environment variety, random vs. curated (§11 #7) — at M4.
- Hyperspace default intensity (§11 #8) — at M4.
- Star brightness defaults (§11 #11) — at M5.
- Ring vantage (§11 #12) — at M5.
- Comet/meteor determinism (§11 #13) — at M2 / M8.
- Reachable rocks for flicking (§11 #14) — at M6.

## First week, concretely
If you want a single near-term target: **get through M1.** A backdrop plus a well-distributed star volume that genuinely feels 3D on the device is the proof the whole concept depends on, and it's only a few days. Everything after M1 is additive.
