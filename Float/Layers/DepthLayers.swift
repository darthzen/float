import RealityKit
import UIKit

// §7b transition flash — a brief full-view fade that masks a scene change. Kept from the
// (now retired) generated L1–L4 pipeline because the spatial-image scene system still uses
// it to mask a jump/select between skies. Everything else that lived here — the generated
// far backdrop, L2 nebula (splat/particle), L3 star volume, L4 phenomena — was removed when
// the app moved to a pre-rendered stereo-image library (see SpatialImageEnvironment).
// Fades to BLACK, not white (device round 7). A white flash masks a change by
// saturating, but between two dark deep-space scenes it reads as a jolt — the eye is
// dark-adapted and gets slammed to full brightness and back. Black masks just as
// completely (alpha 1 fully occludes either way) and costs the viewer nothing.
// Type names still say "Whiteout" so this stays a one-file change; see FADE_TINT.
struct WhiteoutComponent: Component {
    var active = false
    var elapsed: TimeInterval = 0
    var fadeIn: TimeInterval = 0.25
    /// MINIMUM time parked at full black. The overlay stays at peak past this for as long as
    /// `holding` is true.
    var hold: TimeInterval = 0.12
    var fadeOut: TimeInterval = 0.45

    /// While true the overlay parks at full black instead of beginning its fade-out, and its
    /// clock stops at the end of `hold`. `AppModel.maskedSwap` clears it once the new sky is
    /// mounted, which is what starts the reveal.
    ///
    /// This exists because a scene swap is not instantaneous — decoding the next sky takes
    /// seconds. With a fixed-length flash the reveal ran on schedule and uncovered the sphere
    /// that was still mounted, i.e. the OLD sky; the load then landed and cut to the new one
    /// with no mask left to hide it. On device that reads as: fade to black, back to where you
    /// were, then a jump. A mask has to outlast the work it is masking, so the fade-out is
    /// driven by the load finishing, not by a timer guessing how long it will take.
    var holding = false

    /// Length of the flash when nothing extends the hold.
    var total: TimeInterval { fadeIn + hold + fadeOut }
}

/// 0 = black, 1 = white. One constant, used by both the per-frame tint and the initial
/// material, so they can never disagree.
let FADE_TINT: CGFloat = 0

struct WhiteoutSystem: System {
    static let query = EntityQuery(where: .has(WhiteoutComponent.self))
    init(scene: Scene) {}
    func update(context: SceneUpdateContext) {
        MainActor.assumeIsolated {
            for e in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
                guard var c = e.components[WhiteoutComponent.self], c.active,
                      let me = e as? ModelEntity else { continue }
                c.elapsed += context.deltaTime
                let peakEnd = c.fadeIn + c.hold
                // Park the clock (not just the alpha) at the end of the hold while holding, so
                // release always drops straight into the fade-out however long the wait was.
                if c.holding { c.elapsed = min(c.elapsed, peakEnd) }
                var a: Float
                if c.elapsed < c.fadeIn {
                    a = Float(c.elapsed / c.fadeIn)                                   // fade to black
                } else if c.elapsed <= peakEnd {
                    a = 1                                                            // peak (swap happens here)
                } else if c.elapsed < c.total {
                    a = Float(1 - (c.elapsed - peakEnd) / c.fadeOut)                   // reveal new env
                } else {
                    a = 0; c.active = false
                }
                a = max(0, min(1, a))
                var mat = UnlitMaterial()
                mat.color = .init(tint: UIColor(white: FADE_TINT, alpha: CGFloat(a)), texture: nil)
                mat.blending = .transparent(opacity: 1.0)
                me.model?.materials = [mat]
                e.components[WhiteoutComponent.self] = c
            }
        }
    }

    // Inward sphere just inside all content; alpha 0 until a jump/select flashes it (§7b).
    @MainActor
    static func makeEntity() -> ModelEntity {
        var mat = UnlitMaterial()
        mat.color = .init(tint: UIColor(white: FADE_TINT, alpha: 0), texture: nil)
        mat.blending = .transparent(opacity: 1.0)
        let e = ModelEntity(mesh: .generateSphere(radius: 1.5), materials: [mat])
        e.name = "Whiteout"
        e.scale.z = -1   // render the inside
        e.components.set(WhiteoutComponent())
        return e
    }
}
