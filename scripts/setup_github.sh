#!/usr/bin/env bash
#
# setup_github.sh — create the Float GitHub repo + ticket queue for farming to Ollama.
#
# Creates: an (empty) repo, labels, milestones M0–M9, and all issues.
# Does NOT push any code. Run AFTER entire.io is set up if you also intend to commit,
# but repo/issue creation itself is safe to run any time.
#
# Requires: gh (authenticated as darthzen — `gh auth status`). Does NOT use a hardcoded PAT.
#
set -euo pipefail

# ----- config (review before running) ---------------------------------------
OWNER="darthzen"
REPO="float"
VISIBILITY="private"          # private | public
DESC="Float — immersive 'floating in deep space' experience for Apple Vision Pro (visionOS)"
MAKE_PROJECT=0                # 1 = also create a GitHub Projects v2 board (needs 'project' scope)
# -----------------------------------------------------------------------------

REPO_FQ="$OWNER/$REPO"
echo ">> Target repo: $REPO_FQ ($VISIBILITY)"
command -v gh >/dev/null || { echo "gh not found — install GitHub CLI and 'gh auth login' as $OWNER"; exit 1; }
gh auth status >/dev/null || { echo "gh not authenticated — run 'gh auth login'"; exit 1; }

# ----- repo ------------------------------------------------------------------
if gh repo view "$REPO_FQ" >/dev/null 2>&1; then
  echo ">> repo exists, skipping create"
else
  echo ">> creating repo"
  gh repo create "$REPO_FQ" --"$VISIBILITY" --description "$DESC" --disable-wiki
fi

# ----- labels ----------------------------------------------------------------
mklabel() { gh label create "$1" --repo "$REPO_FQ" --color "$2" --description "$3" --force >/dev/null; }
echo ">> labels"
mklabel "agent:ollama-ready" "0e8a16" "Safe to farm to an Ollama LLM agent from spec + scaffold"
mklabel "agent:needs-human"  "b60205" "Needs a person in the headset or human judgement — do not auto-farm"
mklabel "risk:high"          "d93f0b" "High risk / make-or-break"
mklabel "risk:med"           "fbca04" "Medium risk"
mklabel "type:setup"         "c5def5" "Project/tooling setup"
mklabel "type:feature"       "1d76db" "Feature implementation"
mklabel "type:interaction"   "5319e7" "Hand tracking / gestures / input"
mklabel "type:content"       "0052cc" "Bodies / textures / visual content"
mklabel "type:comfort"       "006b75" "Comfort / vection / eye-strain"
mklabel "type:perf"          "e99695" "Performance / frame budget"
mklabel "type:test"          "bfdadc" "On-device validation / sign-off"
mklabel "type:infra"         "d4c5f9" "Persistence / migration / plumbing"

# ----- milestones ------------------------------------------------------------
mkms() { gh api "repos/$REPO_FQ/milestones" -f title="$1" -f description="$2" >/dev/null 2>&1 || true; }
echo ">> milestones"
mkms "M0 — Bootstrap"                  "Project builds, deploys, opens an empty full immersive space."
mkms "M1 — Prove depth"                "Backdrop + star volume that genuinely feels 3D on-device. HARD GATE."
mkms "M2 — Clock + nebula + phenomena" "Global clock, nebula (particle fallback + splat stub), comets/meteors."
mkms "M3 — Interaction spine"          "Double-pinch panel + TimeScale slider; de-risk gesture conflict."
mkms "M4 — Environments + hyperspace"  "Deterministic env config, regeneration, hyperspace jump (comfort-gated)."
mkms "M5 — Celestial bodies"           "Planet + two-tier rings + star/sun; Sol System preset."
mkms "M6 — Asteroid field + flick"     "Safe-drift instanced field; tame rocks; fingertip-collider flick."
mkms "M7 — Impacts + fragmentation"    "Active-zone physics, pre-fracture shatter, safety override (perf-gated)."
mkms "M8 — Saved locations"            "Capture/restore places from seed + simTime + thumbnail."
mkms "M9 — Polish + hardening"         "Perf hardening, comfort settings, generator-version guard, splat swap-in."

# ----- issue helper ----------------------------------------------------------
# issue <milestone-title> <comma-labels> <title> <body>
issue() {
  gh issue create --repo "$REPO_FQ" --milestone "$1" --label "$2" --title "$3" --body "$4" >/dev/null
  echo "   + $3"
}
echo ">> issues"

# ---- M0 ----
issue "M0 — Bootstrap" "type:setup,agent:ollama-ready" \
"Generate Xcode project via XcodeGen" \
"$(cat <<'EOF'
**Context:** project.yml defines the visionOS app target (§project.yml, README).
**Do:** run `xcodegen generate`; open Float.xcodeproj; set Team + bundle id; confirm it builds an empty app.
**Acceptance:** project opens and builds without errors on a Mac with the visionOS 27 SDK.
**Depends on:** —
EOF
)"

issue "M0 — Bootstrap" "type:test,agent:needs-human" \
"On-device: app launches and opens/exits full immersive space" \
"$(cat <<'EOF'
**Context:** §1 full immersion, §7 hand-tracking auth.
**Do:** deploy to Vision Pro; Enter → full immersive space opens; exit works; hand-tracking auth prompt appears.
**Acceptance:** clean enter/exit on device; auth prompt fires.
**Needs human:** requires the headset.
EOF
)"

# ---- M1 (HARD GATE) ----
issue "M1 — Prove depth" "type:feature,agent:ollama-ready" \
"Implement L1 far backdrop (inward unlit equirect sphere)" \
"$(cat <<'EOF'
**Context:** §4, Layers/DepthLayers.swift `FarBackdrop`.
**Do:** giant inward sphere (~1000 m), UnlitMaterial with an equirectangular/cubemap texture; scale.z = -1 to face inward; use a placeholder texture for now.
**Acceptance:** a seamless star backdrop fills the FOV with no visible pole pinch at rest.
**Depends on:** —
EOF
)"

issue "M1 — Prove depth" "type:feature,risk:high,agent:ollama-ready" \
"Implement L3 star volume (instanced points, 3D shell + density falloff)" \
"$(cat <<'EOF'
**Context:** §2/§3 — this is the primary depth mechanism. Layers/DepthLayers.swift `StarVolume`.
**Do:** distribute N points across ~2–200 m in a 3D shell with density falloff (NOT one radius); prefer LowLevelMesh instanced points; vary brightness/size by distance; seed from `gen.starStream()` (deterministic, §5).
**Acceptance:** near stars visibly parallax against far stars when the head translates; keep structure inside ~50 m for stereo.
**Depends on:** —
EOF
)"

issue "M1 — Prove depth" "type:test,risk:high,agent:needs-human" \
"DEPTH GATE: verify it genuinely feels 3D on-device" \
"$(cat <<'EOF'
**Context:** §2 — the whole concept rides on this (BUILD_PLAN M1 hard gate).
**Do:** stand in backdrop + star volume; lean and turn; confirm strong stereo + parallax.
**Acceptance:** it reads as genuinely 3D, not a painted dome. If not, fix star distribution before ANY later milestone.
**Needs human:** requires the headset. This gate blocks M2+.
**Depends on:** L1 backdrop, L3 star volume.
EOF
)"

# ---- M2 ----
issue "M2 — Clock + nebula + phenomena" "type:feature,agent:ollama-ready" \
"Implement AnimationClock + ClockSystem (simTime / timeScale)" \
"$(cat <<'EOF'
**Context:** §5 one clock. Animation/AnimationClock.swift.
**Do:** advance `simTime += deltaTime * timeScale` each frame via the ECS System; expose a shared handle layers can sample; support restore(simTime,timeScale) for §7e.
**Acceptance:** a test animation driven only by simTime speeds/slows/freezes with timeScale.
**Depends on:** —
EOF
)"

issue "M2 — Clock + nebula + phenomena" "type:feature,agent:ollama-ready" \
"Wire star twinkle + global drift to simTime" \
"$(cat <<'EOF'
**Context:** §5 animation table.
**Do:** subtle per-star brightness noise + very slow global yaw of L2/L3, all as pure functions of (seed, simTime).
**Acceptance:** motion is deterministic and scales with timeScale; freeze at 0.
**Depends on:** AnimationClock, L3 star volume.
EOF
)"

issue "M2 — Clock + nebula + phenomena" "type:feature,agent:ollama-ready" \
"NebulaVolume protocol + particle fallback backend" \
"$(cat <<'EOF'
**Context:** §10 swappable backend, L2. Layers/DepthLayers.swift.
**Do:** implement `ParticleNebula` — additive soft-particle clouds + a few billboard sheets at varied depths; animate palette off simTime.
**Acceptance:** nebula shows volumetric depth (parallax), not a flat wall; deterministic from `gen.nebulaStream()`.
**Depends on:** AnimationClock. Open decision §11 #2 (backend commit).
EOF
)"

issue "M2 — Clock + nebula + phenomena" "type:feature,agent:ollama-ready" \
"Splat nebula backend stub (visionOS 27)" \
"$(cat <<'EOF'
**Context:** §10, L2 `SplatNebula`.
**Do:** stub the native RealityKit Gaussian-splat path behind `NebulaBackendRenderer`; keep it selectable via EnvironmentConfig.nebulaBackend without touching other layers.
**Acceptance:** switching backend does not affect L1/L3/L4; splat path compiles even if empty.
**Depends on:** NebulaVolume protocol.
EOF
)"

issue "M2 — Clock + nebula + phenomena" "type:feature,agent:ollama-ready" \
"L4 comet / meteor spawner + trails" \
"$(cat <<'EOF'
**Context:** §6, Layers/DepthLayers.swift `PhenomenaSpawner`.
**Do:** interval spawner scaled by timeScale; comets = bright head + particle trail; meteors = fast short streaks; pool entities; keep phenomena mostly beyond ~5 m.
**Acceptance:** occasional comets/meteors cross the volume; counts capped; no allocation hitches.
**Depends on:** AnimationClock. Open decision §11 #13 (determinism).
EOF
)"

issue "M2 — Clock + nebula + phenomena" "type:perf,agent:needs-human" \
"On-device: hold 90 fps with backdrop + stars + particle nebula" \
"$(cat <<'EOF'
**Context:** §4 perf budget.
**Do:** profile on device with L1+L3+particle nebula+phenomena.
**Acceptance:** sustained 90 fps; note the fill-rate headroom for later layers.
**Needs human:** requires the headset + Instruments.
EOF
)"

# ---- M3 ----
issue "M3 — Interaction spine" "type:interaction,agent:ollama-ready" \
"ARKit hand-tracking session + provider loop (90 Hz)" \
"$(cat <<'EOF'
**Context:** §7, Immersive/ImmersiveView.swift `runHandTracking`.
**Do:** start ARKitSession + HandTrackingProvider; stream joint transforms to the gesture detectors each update.
**Acceptance:** thumb/index tip positions available at ~90 Hz inside the immersive space.
**Depends on:** M0.
EOF
)"

issue "M3 — Interaction spine" "type:interaction,risk:high,agent:ollama-ready" \
"Double-pinch detector (hysteresis + system-tap disambiguation)" \
"$(cat <<'EOF'
**Context:** §7 — riskiest interaction. Interaction/Interaction.swift `DoublePinchDetector`.
**Do:** pinch = thumb-index distance below/above enter/exit thresholds (hysteresis); double = two cycles within ~350–450 ms same hand. Arm only when gaze is off interactive UI to avoid the system 'tap'. Consider SpatialEventGesture/GestureComponent instead of raw joints.
**Acceptance:** reliable double-pinch with low false-trigger rate; does not fight system selection.
**Depends on:** hand-tracking loop.
EOF
)"

issue "M3 — Interaction spine" "type:interaction,agent:ollama-ready" \
"Control panel attachment + TimeScale slider" \
"$(cat <<'EOF'
**Context:** §7, Interaction/Interaction.swift `ControlPanelView`.
**Do:** SwiftUI panel in a ViewAttachment at a fixed comfortable distance; slider writes clock.timeScale (0…10, 0 = freeze); New Environment + Save This Spot buttons wired to stubs.
**Acceptance:** slider scales all motion incl. freeze; panel holds still while reached for.
**Depends on:** AnimationClock. Open decision §11 #5 (range).
EOF
)"

issue "M3 — Interaction spine" "type:interaction,agent:ollama-ready" \
"Panel reveal / dismiss + auto-hide" \
"$(cat <<'EOF'
**Context:** §7.
**Do:** double-pinch reveals panel with fade (PresentationComponent); dismiss via second double-pinch, close control, or idle auto-hide.
**Acceptance:** open/close feels intentional; no accidental reveals during normal viewing.
**Depends on:** double-pinch detector, control panel.
EOF
)"

issue "M3 — Interaction spine" "type:test,agent:needs-human" \
"On-device: gesture false-trigger rate" \
"$(cat <<'EOF'
**Context:** §7 conflict risk.
**Do:** use the app normally for a few minutes; count accidental reveals and missed intentional double-pinches.
**Acceptance:** low false-trigger and low miss rate; tune thresholds.
**Needs human:** requires the headset.
EOF
)"

# ---- M4 (comfort gate) ----
issue "M4 — Environments + hyperspace" "type:feature,agent:ollama-ready" \
"EnvironmentConfig + deterministic generator wiring" \
"$(cat <<'EOF'
**Context:** §7a, Environment/*.
**Do:** finish EnvironmentConfig.random() variety; make SceneBuilder rebuild fully from a config via seeded sub-streams; same config ⇒ same universe.
**Acceptance:** two builds from one config are pixel-stable (deterministic layer).
**Depends on:** M1, M2. Open decision §11 #7 (variety).
EOF
)"

issue "M4 — Environments + hyperspace" "type:feature,agent:ollama-ready" \
"'New Environment' regeneration (roll config + rebuild behind current)" \
"$(cat <<'EOF'
**Context:** §7a.
**Do:** New Environment rolls a new config and builds the next universe behind the current one (no loading gap), ready for the jump to swap.
**Acceptance:** regeneration has no visible hitch.
**Depends on:** EnvironmentConfig wiring.
EOF
)"

issue "M4 — Environments + hyperspace" "type:feature,risk:high,agent:ollama-ready" \
"Hyperspace transition sequence (streak / rush / whiteout / arrival)" \
"$(cat <<'EOF'
**Context:** §7b — highest comfort-risk feature.
**Do:** anticipate → L3 stars stretch to radial streaks and rush past (velocity-aligned scaling; camera does NOT translate) → whiteout masks asset swap → recontract into new field.
**Acceptance:** ~1.5–3 s; camera stationary; new environment swapped under the whiteout.
**Depends on:** L3 star volume, regeneration.
EOF
)"

issue "M4 — Environments + hyperspace" "type:comfort,risk:high,agent:ollama-ready" \
"Hyperspace comfort mitigations + intensity setting" \
"$(cat <<'EOF'
**Context:** §7b/§9 — required, not optional.
**Do:** peripheral vignette/dim during rush; short duration; user-initiated only; ease in/out; comfort-intensity setting (full <-> reduced <-> plain crossfade).
**Acceptance:** intensity setting works; 'reduced' available as default (open decision §11 #8).
**Depends on:** hyperspace transition.
EOF
)"

issue "M4 — Environments + hyperspace" "type:test,risk:high,agent:needs-human" \
"On-device: hyperspace comfort test with 2–3 people" \
"$(cat <<'EOF'
**Context:** §7b — vection tolerance varies; do NOT rely on your own tolerance.
**Do:** have 2–3 people run the jump at default intensity.
**Acceptance:** reported as exciting, not sickening. If borderline, default to 'reduced'.
**Needs human:** requires headset + multiple testers.
EOF
)"

# ---- M5 ----
issue "M5 — Celestial bodies" "type:content,agent:ollama-ready" \
"Planet body: textured sphere + star-lit terminator" \
"$(cat <<'EOF'
**Context:** §7c, Bodies/CelestialBodies.swift.
**Do:** sphere with equirect map at fixed hero distance; DirectionalLight from the local star for a day/night terminator; slow spin off the clock.
**Acceptance:** a recognizable lit planet with a clear terminator; no surface-LOD needed.
**Depends on:** M4.
EOF
)"

issue "M5 — Celestial bodies" "type:content,agent:ollama-ready" \
"Atmosphere limb glow + optional cloud shell" \
"$(cat <<'EOF'
**Context:** §7c.
**Do:** fresnel-rim transparent shell for atmosphere; optional second transparent cloud sphere rotating at a different rate; gas-giant banding via scrolling shader noise.
**Acceptance:** planet reads convincingly; clouds add parallax.
**Depends on:** planet body.
EOF
)"

issue "M5 — Celestial bodies" "type:content,agent:ollama-ready" \
"Two-tier rings: bulk band + close-resolvable instanced debris" \
"$(cat <<'EOF'
**Context:** §7c two-tier rings; reuses M6 asteroid instancing.
**Do:** flat textured annulus (Cassini gaps) for the bulk; LOD-gated instanced rock belt on the near arc that resolves up close; in-plane orbit off the clock; near debris honors the §7d safety bubble if vantage is in-plane.
**Acceptance:** ring reads as a band at distance and resolves into individual rocks up close.
**Depends on:** planet body, asteroid instancing (M6). Open decision §11 #12 (ring vantage).
EOF
)"

issue "M5 — Celestial bodies" "type:content,risk:med,agent:ollama-ready" \
"Star / Sun body: emissive + corona + flares (luminance-capped)" \
"$(cat <<'EOF'
**Context:** §7c, §9 eye-strain.
**Do:** emissive sphere (granulation shader), limb darkening, corona sprites, occasional flares; CAP peak luminance + angular size; contain bloom.
**Acceptance:** dramatic but not fatiguing; does not fill the FOV.
**Depends on:** M4. Open decision §11 #11 (brightness defaults).
EOF
)"

issue "M5 — Celestial bodies" "type:content,agent:needs-human" \
"Sol System preset + NASA asset licensing verification" \
"$(cat <<'EOF'
**Context:** §7c/§8 — NASA/JPL maps are generally public domain but verify per asset.
**Do:** wire a curated 'Sol System' config placing a real body (correct texture/rings); collect the maps; verify each asset's license + attribution.
**Acceptance:** recognizable Sol-System scene; licenses confirmed and recorded.
**Needs human:** licensing judgement.
**Depends on:** planet + rings.
EOF
)"

# ---- M6 ----
issue "M6 — Asteroid field + flick" "type:feature,risk:med,agent:ollama-ready" \
"Instanced asteroid field with safe-drift spawner (bubble guaranteed)" \
"$(cat <<'EOF'
**Context:** §7d, Bodies/AsteroidField.swift — premium depth element.
**Do:** instanced rocky meshes; spawn on lateral drift whose closest-approach to origin exceeds safetyRadius (guaranteed at spawn, no runtime avoidance); axial tumble ok; conveyor respawn; lit by the star.
**Acceptance:** dense field reads strongly 3D; NOTHING ever enters the safety bubble.
**Depends on:** M4.
EOF
)"

issue "M6 — Asteroid field + flick" "type:feature,agent:ollama-ready" \
"Tame reachable rocks for flicking" \
"$(cat <<'EOF'
**Context:** §7f reachability reconciliation.
**Do:** a small set of slow 'tame' rocks that drift at arm's reach (~0.5–0.8 m), separate population from the ambient hazard field.
**Acceptance:** a few reachable rocks present without cluttering the near field.
**Depends on:** asteroid field. Open decision §11 #14 (always-present vs summon gesture).
EOF
)"

issue "M6 — Asteroid field + flick" "type:interaction,agent:ollama-ready" \
"Fingertip-collider flick + mass-scaled impulse" \
"$(cat <<'EOF'
**Context:** §7f, Interaction/Interaction.swift `FlickInteraction`.
**Do:** kinematic fingertip collider from hand joints; on contact with a tame rock apply impulse ∝ smoothed hand velocity, scaled by 1/mass; outward only.
**Acceptance:** flicking a tame rock sends it tumbling away believably; big rocks barely move.
**Depends on:** hand-tracking loop, tame rocks.
EOF
)"

issue "M6 — Asteroid field + flick" "type:test,agent:needs-human" \
"On-device: field never approaches the head; flick feels right" \
"$(cat <<'EOF'
**Context:** §7d/§9 safety, §7f feel.
**Do:** sit in a dense field; confirm nothing looms; flick several rocks.
**Acceptance:** zero head approaches; flick feels natural.
**Needs human:** requires the headset.
EOF
)"

# ---- M7 (perf gate) ----
issue "M7 — Impacts + fragmentation" "type:feature,risk:high,agent:ollama-ready" \
"Active-zone rigid-body promotion" \
"$(cat <<'EOF'
**Context:** §7d emergent layer, Bodies/AsteroidImpactSystem.swift.
**Do:** promote rocks entering an 'active zone' to dynamic rigid bodies (PhysicsBody + Collision); seeded crossing trajectories collide; distant rocks stay kinematic.
**Acceptance:** rocks collide in the active zone; cost bounded to that zone.
**Depends on:** asteroid field.
EOF
)"

issue "M7 — Impacts + fragmentation" "type:feature,risk:high,agent:ollama-ready" \
"Pre-fracture fragment authoring + swap-on-impact" \
"$(cat <<'EOF'
**Context:** §7d recommended fragmentation.
**Do:** author each rock offline with a precomputed Voronoi fragment set; on impact > energy threshold swap intact rock for fragments inheriting velocity + impulse.
**Acceptance:** convincing shatter with no runtime mesh fracture; fragment counts capped.
**Depends on:** rigid-body promotion.
EOF
)"

issue "M7 — Impacts + fragmentation" "type:content,agent:ollama-ready" \
"Dust / spark burst on impact" \
"$(cat <<'EOF'
**Context:** §7d, L4 particles.
**Do:** emit a short additive dust/spark burst at the contact point on shatter.
**Acceptance:** impacts read as energetic; bursts despawn cleanly.
**Depends on:** rigid-body promotion.
EOF
)"

issue "M7 — Impacts + fragmentation" "type:comfort,risk:high,agent:ollama-ready" \
"Safety override: fade head-bound fragments before the bubble" \
"$(cat <<'EOF'
**Context:** §7d/§9 hard rule — the bubble wins.
**Do:** any fragment on a head-bound path is allowed to begin its arc then FADES OUT before the safety bubble (deflection only as fallback); keep impacts out in the field.
**Acceptance:** you see impacts begin but nothing ever reaches the face.
**Depends on:** rigid-body promotion.
EOF
)"

issue "M7 — Impacts + fragmentation" "type:perf,risk:high,agent:needs-human" \
"On-device: 90 fps under worst-case impacts" \
"$(cat <<'EOF'
**Context:** §7d — heaviest system.
**Do:** trigger many simultaneous impacts; profile.
**Acceptance:** sustained 90 fps under worst case; tune caps if not.
**Needs human:** requires headset + Instruments.
EOF
)"

# ---- M8 ----
issue "M8 — Saved locations" "type:feature,agent:ollama-ready" \
"SavedLocation capture (config + simTime + timeScale + thumbnail)" \
"$(cat <<'EOF'
**Context:** §7e, Persistence/SavedLocation.swift.
**Do:** 'Save This Spot' captures EnvironmentConfig + simTime + timeScale + a rendered thumbnail + generator-version; persist via Codable JSON + image files (or SwiftData).
**Acceptance:** a save is tiny (config + clock + thumbnail), not recorded positions.
**Depends on:** EnvironmentConfig wiring.
EOF
)"

issue "M8 — Saved locations" "type:feature,agent:ollama-ready" \
"Places gallery UI" \
"$(cat <<'EOF'
**Context:** §7e.
**Do:** a 'Places' gallery of saved thumbnails to browse and select.
**Acceptance:** saved spots listed with thumbnails; selecting one triggers restore.
**Depends on:** SavedLocation capture.
EOF
)"

issue "M8 — Saved locations" "type:feature,agent:ollama-ready" \
"Restore via jump + determinism verification" \
"$(cat <<'EOF'
**Context:** §7e.
**Do:** restore regenerates from seed and sets simTime/timeScale; arrive via the hyperspace jump; asteroid-impact layer replays from initial conditions.
**Acceptance:** deterministic layer matches exactly on return; impact scenario replays (may differ) by design.
**Depends on:** regeneration, SavedLocation capture.
EOF
)"

# ---- M9 ----
issue "M9 — Polish + hardening" "type:perf,agent:needs-human" \
"Perf hardening to the resolution budget" \
"$(cat <<'EOF'
**Context:** §4 — resolution is a tuning outcome.
**Do:** push texture/splat/star budgets to the max that holds 90 fps across environments.
**Acceptance:** sustained 90 fps everywhere; documented budget.
**Needs human:** requires headset + Instruments.
EOF
)"

issue "M9 — Polish + hardening" "type:comfort,agent:ollama-ready" \
"Surface comfort settings" \
"$(cat <<'EOF'
**Context:** §9.
**Do:** expose hyperspace intensity and any other comfort toggles in a settings surface.
**Acceptance:** users can dial comfort without code changes.
**Depends on:** M4 comfort mitigations.
EOF
)"

issue "M9 — Polish + hardening" "type:infra,agent:ollama-ready" \
"Generator-version migration guard" \
"$(cat <<'EOF'
**Context:** §7e caveat.
**Do:** store generatorVersion with saves; keep old generators available (or migrate) so saved spots don't drift after algorithm changes.
**Acceptance:** loading an old save reproduces its universe or migrates cleanly.
**Depends on:** SavedLocation capture.
EOF
)"

issue "M9 — Polish + hardening" "type:feature,agent:ollama-ready" \
"Swap in Gaussian-splat nebula backend if API is stable" \
"$(cat <<'EOF'
**Context:** §10, §7c-nebula.
**Do:** if the visionOS 27 splat API has stabilized, implement SplatNebula for real and make it the default backend.
**Acceptance:** splat nebula renders with volumetric depth; particle fallback still selectable.
**Depends on:** splat backend stub.
EOF
)"

# ----- optional GitHub Projects v2 board -------------------------------------
if [ "$MAKE_PROJECT" = "1" ]; then
  echo ">> creating Projects v2 board (needs 'project' scope on the token)"
  gh project create --owner "$OWNER" --title "Float" || echo "   (project create failed — check 'project' scope)"
  echo "   Add issues to the board via: gh project item-add <number> --owner $OWNER --url <issue-url>"
fi

echo ">> done. Review issues: gh issue list --repo $REPO_FQ --limit 100"
