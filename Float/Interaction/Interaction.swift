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

/// §7 — the in-scene control panel (ViewAttachment). Trimmed to what the spatial-image app
/// needs: a random-scene jump and save. (The old time-speed slider drove generated animation
/// that no longer exists; the flick-an-asteroid interaction went with the asteroid layer.)
struct ControlPanelView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 20) {
            Button("Random Scene") { model.randomScene() }
            Button("Save This Spot") {
                // §7e capture current sceneName + thumbnail.
            }
        }
        .padding(28)
        .glassBackgroundEffect()
        .frame(width: 320)
    }
}
