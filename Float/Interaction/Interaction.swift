import SwiftUI
import RealityKit
import ARKit
import simd

/// §7 — reveal gesture. Two thumb+index pinch/release cycles within ~350–450 ms.
/// WARNING: a single pinch is the system "tap" — arm this only when gaze is off UI (§7).
@MainActor
final class DoublePinchDetector {
    var onDoublePinch: (() -> Void)?

    // Hysteresis thresholds (metres) so one slow pinch isn't read as two.
    private let pinchOn: Float = 0.015
    private let pinchOff: Float = 0.03
    /// Max gap between the two pinch *releases* (§7: two cycles inside ~350–450 ms).
    private let window: Double = 0.45

    private var isPinched = false
    private var lastReleaseTime: Double?

    func ingest(thumbTip: SIMD3<Float>, indexTip: SIMD3<Float>, time: Double) {
        let d = simd_distance(thumbTip, indexTip)
        if isPinched {
            guard d > pinchOff else { return }
            isPinched = false
            if let prev = lastReleaseTime, time - prev <= window {
                lastReleaseTime = nil
                onDoublePinch?()
            } else {
                lastReleaseTime = time
            }
        } else if d < pinchOn {
            isPinched = true
            // A first release too old to pair with the cycle starting now is stale.
            if let prev = lastReleaseTime, time - prev > window { lastReleaseTime = nil }
        }
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
