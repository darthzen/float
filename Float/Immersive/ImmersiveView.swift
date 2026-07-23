import SwiftUI
import RealityKit
import ARKit

/// Hosts the RealityKit scene. Since the generated L1–L4 pipeline was retired, the scene is
/// now a single `SpatialImageEnvironment` (a stereo-image inward sphere) plus the §7b whiteout
/// overlay used to mask scene changes. Spec: §7 hand tracking.
struct ImmersiveView: View {
    @Environment(AppModel.self) private var model

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
            Task { @MainActor in
                await SpatialImageEnvironment.load(index: model.currentScene, into: scene)
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
        .task { await runHandTracking() }   // §7 reveal gesture
        .upperLimbVisibility(.visible)
    }

    /// ARKit hand-tracking loop (90 Hz on v26+). Feeds the gesture detectors.
    private func runHandTracking() async {
        // TODO: start ARKitSession + HandTrackingProvider; route joints to
        //       DoublePinchDetector (§7).
    }
}
