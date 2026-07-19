# Float — Ticket Index

Human-readable mirror of the issues created by `scripts/setup_github.sh`. The script is the source of truth; this is for review and planning. Full context for each is in the issue body (Context / Do / Acceptance / Depends-on), keyed to spec sections (§).

**Farming rule:** only farm `ollama-ready` tickets whose dependencies are closed. `needs-human` tickets require a person in the headset or human judgement — route to Rick. Milestone order is the dependency order; **M1 is a hard gate**.

## M0 — Bootstrap
- Generate Xcode project via XcodeGen — `ollama-ready`
- On-device: app launches, opens/exits full immersive space — `needs-human`

## M1 — Prove depth (HARD GATE)
- Implement L1 far backdrop (inward unlit equirect sphere) — `ollama-ready`
- Implement L3 star volume (instanced points, 3D shell + falloff) — `ollama-ready`, `risk:high`
- DEPTH GATE: verify it genuinely feels 3D on-device — `needs-human`, `risk:high`

## M2 — Clock + nebula + phenomena
- AnimationClock + ClockSystem (simTime/timeScale) — `ollama-ready`
- Wire star twinkle + global drift to simTime — `ollama-ready`
- NebulaVolume protocol + particle fallback backend — `ollama-ready`
- Splat nebula backend stub (v27) — `ollama-ready`
- L4 comet/meteor spawner + trails — `ollama-ready`
- On-device: 90 fps with backdrop+stars+particle nebula — `needs-human`

## M3 — Interaction spine
- ARKit hand-tracking session + provider loop — `ollama-ready`
- Double-pinch detector (hysteresis + system-tap disambiguation) — `ollama-ready`, `risk:high`
- Control panel attachment + TimeScale slider — `ollama-ready`
- Panel reveal/dismiss + auto-hide — `ollama-ready`
- On-device: gesture false-trigger rate — `needs-human`

## M4 — Environments + hyperspace (COMFORT GATE)
- EnvironmentConfig + deterministic generator wiring — `ollama-ready`
- "New Environment" regeneration — `ollama-ready`
- Hyperspace transition sequence — `ollama-ready`, `risk:high`
- Hyperspace comfort mitigations + intensity setting — `ollama-ready`, `risk:high`
- On-device: hyperspace comfort test with 2–3 people — `needs-human`, `risk:high`

## M5 — Celestial bodies
- Planet body: textured sphere + star-lit terminator — `ollama-ready`
- Atmosphere limb glow + optional cloud shell — `ollama-ready`
- Two-tier rings: bulk band + close-resolvable debris — `ollama-ready`
- Star/Sun body: emissive/corona/flares (luminance-capped) — `ollama-ready`, `risk:med`
- Sol System preset + NASA asset licensing verification — `needs-human`

## M6 — Asteroid field + flick
- Instanced asteroid field w/ safe-drift spawner (bubble guaranteed) — `ollama-ready`, `risk:med`
- Tame reachable rocks for flicking — `ollama-ready`
- Fingertip-collider flick + mass-scaled impulse — `ollama-ready`
- On-device: field never approaches head; flick feels right — `needs-human`

## M7 — Impacts + fragmentation (PERF GATE)
- Active-zone rigid-body promotion — `ollama-ready`, `risk:high`
- Pre-fracture fragment authoring + swap-on-impact — `ollama-ready`, `risk:high`
- Dust/spark burst on impact — `ollama-ready`
- Safety override: fade head-bound fragments before bubble — `ollama-ready`, `risk:high`
- On-device: 90 fps under worst-case impacts — `needs-human`, `risk:high`

## M8 — Saved locations
- SavedLocation capture (config+simTime+timeScale+thumbnail) — `ollama-ready`
- Places gallery UI — `ollama-ready`
- Restore via jump + determinism verification — `ollama-ready`

## M9 — Polish + hardening
- Perf hardening to resolution budget — `needs-human`
- Surface comfort settings — `ollama-ready`
- Generator-version migration guard — `ollama-ready`
- Swap in Gaussian-splat backend if API stable — `ollama-ready`

---

Totals: 36 tickets — ~27 `ollama-ready`, ~9 `needs-human` (on-device feel/comfort/perf sign-offs + asset licensing). The `needs-human` gates are deliberately the ones an LLM can't judge from source alone.
