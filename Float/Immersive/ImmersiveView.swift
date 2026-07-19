import SwiftUI
import RealityKit
import ARKit

/// Hosts the RealityKit scene and wires input providers.
/// Spec: §3 layered scene, §7 hand tracking, §7f flick.
struct ImmersiveView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        RealityView { content, attachments in
            // Register ECS components and systems once.
            ClockComponent.registerComponent()
            StarVolumeComponent.registerComponent()
            StarComponent.registerComponent()
            PhenomenonComponent.registerComponent()
            AnimationClockSystem.registerSystem()
            StarAnimationSystem.registerSystem()
            PhenomenaSystem.registerSystem()
            AsteroidImpactSystem.registerSystem()

            // Build the initial universe from the active config (§7a).
            let root = SceneBuilder.build(config: model.currentConfig, clock: model.clock)
            content.add(root)

            // Attach the (hidden) control panel; revealed by double-pinch (§7).
            if let panel = attachments.entity(for: "controlPanel") {
                panel.isEnabled = false
                root.addChild(panel)
            }
        } update: { _, _ in
            // TODO: react to environment swaps (§7b) — rebuild or crossfade.
        } attachments: {
            Attachment(id: "controlPanel") {
                ControlPanelView().environment(model)
            }
        }
        .task { await runHandTracking() }   // §7 double-pinch, §7f flick
        .upperLimbVisibility(.visible)      // keep hands visible for flicking
    }

    /// ARKit hand-tracking loop (90 Hz on v26+). Feeds the gesture detectors.
    private func runHandTracking() async {
        // TODO: start ARKitSession + HandTrackingProvider; route joints to
        //       DoublePinchDetector (§7) and FlickInteraction (§7f).
    }
}
