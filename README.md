# Float — Immersive Space Starfield (visionOS)

A single-user, fully-immersive "floating alone in deep space" experience for Apple Vision Pro.
Full spec: `../starfield_immersive_spec.md`. Build plan: `BUILD_PLAN.md`.

## Status (read this first)
- This is a **scaffold**: structured stubs with real type/signature shapes and TODOs keyed to spec sections (§).
- It has **not** been compiled — authored on a non-Mac (Linux) environment, so it cannot be built or verified here. Treat it as a starting skeleton, not a running app. Expect to fix imports and signatures against the current visionOS 27 SDK.
- No `.xcodeproj/project.pbxproj` was hand-forged, because an unverified one that fails to open would waste your time. Use `project.yml` (below) instead.
- No git/entire initialization was done here. When you `git init` locally and sync to darthzen, your own entire checkpoint workflow applies — set that up on your Mac.

## Getting a buildable Xcode project (two paths)
1. **XcodeGen (recommended):** `brew install xcodegen`, then from this folder run `xcodegen generate`. It reads `project.yml` and writes `Float.xcodeproj`. Open it, set your Team and bundle id.
2. **Fresh Xcode target:** File → New → Project → visionOS App (RealityKit, Full immersive). Then drag the `Float/` source folders in and merge the keys from `Resources/Info.plist` and `Resources/Float.entitlements`.

## Target
- visionOS 27 (developer beta). Swift 6. RealityKit + ARKit + SwiftUI.
- `project.yml` sets the deployment target to 26.0 for SDK stability; bump to 27 when you adopt splat/projective-light APIs.

## Structure
```
Float/
  App/           app entry (FloatApp), app-level state (AppModel), launcher
  Immersive/     RealityView host (ImmersiveView) + scene assembly (SceneBuilder)
  Environment/   EnvironmentConfig, deterministic EnvironmentGenerator, SeededRandom
  Animation/     global TimeScale clock + ECS system (AnimationClock)
  Layers/        L1 backdrop, L2 nebula (swappable backend), L3 star volume, L4 phenomena
  Bodies/        planets + two-tier rings + star, asteroid field, impact/fragmentation system
  Interaction/   double-pinch detector, control panel, flick interaction
  Persistence/   SavedLocation model + store
  Resources/     Info.plist, Float.entitlements
```

## Foundational rules (do not violate — they hold the whole design together)
- **One clock:** every animated value reads `AnimationClock.simTime`; `timeScale` scales it (§5).
- **Deterministic core:** generation and non-physics animation are pure functions of (seed, simTime) via `SeededRandom` — no wall-clock, no unseeded randomness (§5, §7e).
- **Camera never translates:** only objects move; apparent motion is never the viewer (§9).
- **Safety bubble is absolute:** nothing — ambient drift, impact debris, or a flicked rock rebound — enters the ~2–3 m exclusion sphere (§7d, §9).
- **Comfort is a gate, not polish:** a change that regresses comfort is not done.

## Verify before shipping
- Exact hand-tracking privacy key name in `Info.plist` (`NSHandsTrackingUsageDescription`) against the current SDK — flagged assumption.
- Per-asset licenses for any NASA/ESO textures used (§8).
