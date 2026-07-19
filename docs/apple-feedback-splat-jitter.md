# Apple Feedback draft — Gaussian splat jitter as a full-surround immersive volume

Submit at https://feedbackassistant.apple.com (Platform: visionOS, Type: Incorrect/Unexpected Behavior).
Attach a screen recording of the head-motion jitter if possible.

---

**Title:** visionOS 27: `GaussianSplatComponent` jitters ("shift + bounce") on head motion when used as a full-surround volume in an immersive space

**Area:** RealityKit / visionOS / Gaussian splats

**Environment:**
- Apple Vision Pro (physical device), visionOS 27.0 (beta)
- Xcode-beta 27.0
- Full `ImmersiveSpace`, `.immersionStyle(.constant(.full), in: .full)`
- RealityKit, Swift 6

**Summary:**
A procedurally-generated Gaussian splat cloud rendered as a 360° volume *surrounding* the viewer exhibits a persistent reprojection artifact: with the head still the splats are stable, but on **any head movement** the splats visibly **shift quickly and then snap back to their original world position** each frame ("shift + bounce"). Other RealityKit content in the same scene — meshes, an inward equirectangular backdrop sphere, thousands of instanced point entities — reprojects correctly and is rock-solid. Only the splats jitter.

**Steps to reproduce:**
1. Open a full `ImmersiveSpace`.
2. Build a `GaussianSplatResource` from procedurally-generated buffers via
   `GaussianSplatResource.BufferResource(count:position:scale:rotation:opacity:sphericalHarmonics:)`
   (positions/scales/rotations/opacity as `LowLevelBuffer`s; SH degree `.zero`, i.e. DC-only color).
3. Distribute several thousand splats across a wide radius (e.g. 60–400 m) in **all directions** around the origin (a surrounding volume, not a bounded object in front of the viewer).
4. `entity.components.set(GaussianSplatComponent(resource))`, add to the scene at the origin.
5. Enter the immersive space and move / rotate your head.

**Result:** the splats jitter (shift + bounce) with head motion; stable only when the head is still. Unusable as a stable environment.

**Expected:** splats should reproject with the head pose like all other RealityKit content and stay world-locked during head motion.

**What was tried (none eliminated the jitter):**
- `projectionMode` = `.perspective` **and** `.tangential`
- `sortingMode` = `.depth` **and** `.distance`
- Splat size varied from tiny (~0.1 m) to large (~20 m) and count from a few hundred to several thousand — rules out overdraw / frame-rate.
- Cloud distance pushed from 15 m out to 400 m — reduces apparent magnitude but the shift + bounce persists at all distances.

**Hypothesis:** the splat renderer's reprojection appears tuned for a *bounded object scan* placed in front of the viewer (the documented use case) and does not correctly reproject a large surrounding distribution — possibly the splats don't participate in the compositor's depth-based reprojection, or the per-frame projection lacks motion compensation for wide/omnidirectional splat sets.

**Impact:** blocks using Gaussian splats for volumetric/environmental content (nebulae, fog, dust, room-scale surrounding scans) in immersive spaces — a significant class of experiences.
