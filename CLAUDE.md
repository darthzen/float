# CLAUDE.md — Float project guidance

Project context and rules for any Claude Code / agent session working in this repo. Read alongside `HANDOFF.md`, `starfield_immersive_spec.md`, and `BUILD_PLAN.md`.

## What this is
A single-user, fully-immersive "floating alone in deep space" experience for Apple Vision Pro. visionOS 27 (developer beta), Swift 6, RealityKit + ARKit + SwiftUI. Full immersive space, no passthrough. The full feature spec is `starfield_immersive_spec.md` (sections are referenced as §).

## Foundational engineering rules (do not violate — they hold the design together)
- **One clock (§5):** every animated value reads `AnimationClock.simTime`; `timeScale` scales it. Nothing animates off wall-clock.
- **Deterministic core (§5, §7e):** generation and non-physics animation are pure functions of (seed, `simTime`) via `SeededRandom` — no wall-clock, no unseeded randomness. The one exception is the asteroid impact/fragmentation layer (§7d), which is intentionally free-running; saves restore its initial conditions only.
- **Camera never translates (§9):** only objects move. Apparent motion is never the viewer — this is the core comfort rule.
- **Safety bubble is absolute (§7d, §9):** nothing — ambient drift, impact debris, or a flicked-rock rebound — enters the ~2–3 m exclusion sphere around the head. Enforced at spawn time; debris on a head-bound path fades before the bubble.
- **Comfort is a gate, not polish (§9):** any change that regresses comfort is not done. The hyperspace jump (§7b) is the single highest comfort risk.

## Git / entire.io workflow (Rick's standing rules — mandatory)
- Before ANY commit, verify `.entire/settings.json` exists. If it does not, STOP and tell Rick — do not commit.
- Never claim entire.io is enabled; only verify it.
- This repo syncs to `darthzen` (Rick's own account): keep `.entire/settings.json` and agent hook files committed; let the `entire/checkpoints/v1` branch push normally.
- Never hardcode Rick's PAT. Use the Mac's existing `gh` auth.
- **Mirror registration is a required enable step (not optional).** Enabling + pushing + capturing sessions does NOT put a repo on the entire.io dashboard — only registering it as a cloud mirror does. Whenever enabling entire on a repo, after `entire enable` + `entire agent add claude-code`, run `entire repo mirror create github.com/darthzen/<repo>` and confirm `entire repo mirror list --show-available` shows it as `mirrored` (not `available`). If a repo is ever missing from the dashboard, check this first — it is the usual cause, not transcript/session issues.

## Build / run
- Generate the Xcode project: `xcodegen generate` (needs `brew install xcodegen`). Or create a fresh visionOS App target and add `Float/` sources + `Resources/` keys.
- Deployment target is 27.0 in `project.yml` — required for the native Gaussian-splat / projective-light APIs. vOS26 workarounds (e.g. the large-transparent-quad depth break) no longer apply; do not reintroduce them. Note: intersection/seam artifacts from crossed transparent quads are OS-independent and their guards must stay.
- The scaffold is stubs — expect to fix signatures against the live SDK. It has not been compiled.

## Coding conventions
- Swift 6, `@MainActor` for app/UI state and anything touching RealityKit main-thread APIs.
- Keep TODO markers keyed to spec sections (e.g. `// §7d …`) so intent travels with the code.
- New layers/systems hang off the single `UniverseRoot` entity at the origin.
- Nebula backend is behind `NebulaBackendRenderer` — keep splat vs. particle swappable (§10).

## Ticket workflow (for farming to Ollama)
- Tickets live as GitHub issues (see `docs/TICKETS.md` and `scripts/setup_github.sh`).
- `agent:ollama-ready` = safe to farm to an LLM agent from spec + scaffold.
- `agent:needs-human` = requires a person in the headset or human judgement (on-device feel/comfort/perf sign-offs, asset licensing). Never auto-farm these.
- Respect milestone order (M0→M9); M1 "prove depth" is a hard gate before later work.

## When unsure
- Prefer the spec (`starfield_immersive_spec.md`) as source of truth. If the spec has an open decision (§11), surface it to Rick rather than guessing — several are still open.
