import SwiftUI
import RealityKit
import ARKit

/// Hosts the RealityKit scene. Since the generated L1–L4 pipeline was retired, the scene is
/// now a single `SpatialImageEnvironment` (a stereo-image inward sphere) plus the §7b whiteout
/// overlay used to mask scene changes. Spec: §7 hand tracking.
struct ImmersiveView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        RealityView { content, attachments in
            // Register the ECS components/systems the spatial scene still uses.
            ClockComponent.registerComponent()
            WhiteoutComponent.registerComponent()
            AnimationClockSystem.registerSystem()
            WhiteoutSystem.registerSystem()

            // Persistent container holds the scene; a scene change swaps the sky under it.
            let container = Entity()
            container.name = "SceneContainer"
            content.add(container)
            model.sceneContainer = container

            // The spatial-image environment — an empty container mounted now (so a select
            // works immediately) whose skybox loads async and can be swapped (currentScene).
            let scene = SpatialImageEnvironment.makeContainer()
            container.addChild(scene)
            model.sceneRoot = scene
            if let ready = model.preparedSky {
                // Preloaded by LauncherView before the space opened — attach synchronously
                // so the very first frame of immersion already has the sky in it.
                SpatialImageEnvironment.attach(ready, to: scene)
                model.preparedSky = nil      // consumed; a scene change re-decodes as normal
                model.sceneReady = true
            } else {
                // Preload failed or was skipped — fall back to loading in place. This is the
                // old behaviour, black gap and all, but it only happens if `prepare` returned
                // nil, in which case there is nothing to show either way.
                Task { @MainActor in
                    await SpatialImageEnvironment.load(index: model.currentScene, into: scene)
                    model.sceneReady = true  // drops SplashView (see AppModel.sceneReady)
                }
            }

            // §7b whiteout overlay — a persistent inward white sphere (alpha 0) a jump flashes.
            let whiteout = WhiteoutSystem.makeEntity()
            container.addChild(whiteout)
            model.whiteout = whiteout

            // Hidden control panel, revealed by the two-hand pinch-spread gesture (§7).
            if let panel = attachments.entity(for: "controlPanel") {
                panel.isEnabled = false
                container.addChild(panel)
            }
        } update: { _, _ in
            // Scene changes are driven imperatively via AppModel (it mutates the container).
        } attachments: {
            Attachment(id: "controlPanel") {
                ControlPanelView().environment(model)
            }
        }
        .task { await runHandTracking() }    // §7 reveal gesture
        .task { await runWorldTracking() }   // head pose for AppModel.recenter()
        .upperLimbVisibility(.visible)
    }

    /// Runs a WorldTrackingProvider purely so `AppModel.recenter()` can query the device
    /// (head) anchor on demand. Its own session, kept separate from hand tracking so an
    /// unsupported/denied hand-tracking path can't take recentering down with it. Nothing
    /// is polled per-frame — `queryDeviceAnchor` is called only when the button is pressed.
    private func runWorldTracking() async {
        guard WorldTrackingProvider.isSupported else { return }
        let session = ARKitSession()
        let world = WorldTrackingProvider()
        do { try await session.run([world]) } catch { return }
        model.worldTracking = world

        // Launch auto-recenter: put the sky's front where the user is ALREADY facing rather
        // than making them turn or hunt for the button. Retried rather than called once —
        // the device anchor is not tracked the instant the provider starts, and `sceneRoot`
        // is mounted by the RealityView closure, which need not have run yet. Bounded so a
        // headset that never reports tracking doesn't spin.
        //
        // Scoped to this task's lifetime, which IS the immersive space's lifetime, so it
        // fires once per space open — including a reopen mid-session, where the entities are
        // rebuilt fresh and the previous yaw would otherwise be lost. It deliberately does
        // NOT re-fire on a scene change: the yaw tracks the user's body, not the sky
        // (see AppModel.recenterYaw).
        //
        // In practice this lands hidden behind SplashView, which holds until a ~100 MB
        // stereo HEIC has decoded — far longer than tracking takes to come up.
        let deadline = CACurrentMediaTime() + 3.0
        while CACurrentMediaTime() < deadline, !model.recenter() {
            try? await Task.sleep(for: .milliseconds(50))
        }

        // Hold the session (and so the provider) alive for as long as the immersive view
        // exists; `.task` cancels this on teardown, which drops both.
        for await _ in session.events {}
        model.worldTracking = nil
    }

    /// ARKit hand-tracking loop (90 Hz on v26+). Feeds the §7 double-pinch detector, which
    /// reopens the launcher menu — the only way back to UI once its window has been closed.
    /// (§7's gaze-conflict mitigation is deferred: with no window open there's nothing for
    /// the first pinch's system-tap to land on, which is exactly the reopen case.)
    private func runHandTracking() async {
        guard HandTrackingProvider.isSupported else { return }
        let session = ARKitSession()
        let hands = HandTrackingProvider()
        do { try await session.run([hands]) } catch { return }

        // One detector per hand so alternating-hand pinches don't pair into a "double".
        let detectors: [HandAnchor.Chirality: DoublePinchDetector] =
            [.left: DoublePinchDetector(), .right: DoublePinchDetector()]
        for d in detectors.values {
            d.onDoublePinch = { openWindow(id: "launcher") }
        }

        for await update in hands.anchorUpdates where update.event == .updated {
            let anchor = update.anchor
            guard anchor.isTracked, let skeleton = anchor.handSkeleton else { continue }
            let thumb = skeleton.joint(.thumbTip)
            let index = skeleton.joint(.indexFingerTip)
            guard thumb.isTracked, index.isTracked else { continue }
            // Same-hand tip distance — anchor space suffices, no world transform needed.
            detectors[anchor.chirality]?.ingest(
                thumbTip: translation(of: thumb.anchorFromJointTransform),
                indexTip: translation(of: index.anchorFromJointTransform),
                time: update.timestamp)
        }
    }

    private func translation(of m: simd_float4x4) -> SIMD3<Float> {
        SIMD3(m.columns.3.x, m.columns.3.y, m.columns.3.z)
    }
}
