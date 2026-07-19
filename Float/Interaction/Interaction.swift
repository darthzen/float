import SwiftUI
import RealityKit
import ARKit
import simd

/// §7 — reveal gesture. Two thumb+index pinch/release cycles within ~350–450 ms.
/// WARNING: a single pinch is the system "tap" — arm this only when gaze is off UI (§7).
@MainActor
final class DoublePinchDetector {
    var onDoublePinch: (() -> Void)?
    private var lastPinchEndTime: Double?

    // Hysteresis thresholds (metres) so one slow pinch isn't read as two.
    private let pinchOn: Float = 0.015
    private let pinchOff: Float = 0.03

    func ingest(thumbTip: SIMD3<Float>, indexTip: SIMD3<Float>, time: Double) {
        // TODO: detect pinch enter/exit via distance + hysteresis; if two cycles land
        //       inside the window, fire onDoublePinch() (§7).
        _ = simd_distance(thumbTip, indexTip)
    }
}

/// §7 — the control panel shown as a ViewAttachment. Speed slider + New Environment + Save.
struct ControlPanelView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 20) {
            Text("Time")
            // §7 speed slider → clock.timeScale (0 = freeze).
            Slider(value: Binding(get: { model.clock.timeScale },
                                  set: { model.clock.timeScale = $0 }),
                   in: 0...10)
            Button("New Environment") {
                // §7b hyperspace jump → §7a regenerate. TODO: trigger the transition.
            }
            Button("Save This Spot") {
                // §7e capture config + simTime + timeScale + thumbnail.
            }
        }
        .padding(28)
        .glassBackgroundEffect()
        .frame(width: 320)
    }
}

/// §7f — flick an asteroid. A fingertip collider imparts a mass-scaled impulse.
@MainActor
final class FlickInteraction {
    func ingest(fingertip: SIMD3<Float>, velocity: SIMD3<Float>) {
        // TODO: kinematic fingertip collider; on contact with a (tame) rock, apply an
        //       impulse proportional to hand velocity and inversely to mass. Outward only;
        //       any rebound toward the head still hits the §9 fade/deflect bubble.
    }
}
