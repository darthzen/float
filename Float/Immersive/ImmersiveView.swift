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
            WhiteoutComponent.registerComponent()
            AnimationClockSystem.registerSystem()
            StarAnimationSystem.registerSystem()
            PhenomenaSystem.registerSystem()
            AsteroidImpactSystem.registerSystem()
            WhiteoutSystem.registerSystem()

            // Persistent container holds the universe root; environment swaps (§7b) add a
            // new "UniverseRoot" and crossfade out the old one, all under this container.
            let container = Entity()
            container.name = "SceneContainer"
            container.addChild(SceneBuilder.build(config: model.currentConfig, clock: model.clock))
            content.add(container)
            model.sceneContainer = container

            // §7b whiteout overlay — a persistent inward white sphere (alpha 0) the jump flashes.
            let whiteout = WhiteoutSystem.makeEntity()
            container.addChild(whiteout)
            model.whiteout = whiteout

            // Attach the (hidden) control panel to the container so it survives swaps;
            // revealed by the two-hand pinch-spread gesture (§7, float-reveal-gesture).
            if let panel = attachments.entity(for: "controlPanel") {
                panel.isEnabled = false
                container.addChild(panel)
            }
        } update: { _, _ in
            // Environment swaps are driven imperatively via AppModel.newEnvironment()
            // (it mutates the container directly), so nothing to reconcile here.
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
