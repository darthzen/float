import RealityKit
import UIKit

// §7b whiteout — a brief full-view white flash that masks a scene change. Kept from the
// (now retired) generated L1–L4 pipeline because the spatial-image scene system still uses
// it to mask a jump/select between skies. Everything else that lived here — the generated
// far backdrop, L2 nebula (splat/particle), L3 star volume, L4 phenomena — was removed when
// the app moved to a pre-rendered stereo-image library (see SpatialImageEnvironment).
struct WhiteoutComponent: Component {
    var active = false
    var elapsed: TimeInterval = 0
    var fadeIn: TimeInterval = 0.25
    var hold: TimeInterval = 0.12
    var fadeOut: TimeInterval = 0.45
    var total: TimeInterval { fadeIn + hold + fadeOut }
}

struct WhiteoutSystem: System {
    static let query = EntityQuery(where: .has(WhiteoutComponent.self))
    init(scene: Scene) {}
    func update(context: SceneUpdateContext) {
        MainActor.assumeIsolated {
            for e in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
                guard var c = e.components[WhiteoutComponent.self], c.active,
                      let me = e as? ModelEntity else { continue }
                c.elapsed += context.deltaTime
                var a: Float
                if c.elapsed < c.fadeIn {
                    a = Float(c.elapsed / c.fadeIn)                                   // fade to white
                } else if c.elapsed < c.fadeIn + c.hold {
                    a = 1                                                            // peak (swap happens here)
                } else if c.elapsed < c.total {
                    a = Float(1 - (c.elapsed - c.fadeIn - c.hold) / c.fadeOut)         // reveal new env
                } else {
                    a = 0; c.active = false
                }
                a = max(0, min(1, a))
                var mat = UnlitMaterial()
                mat.color = .init(tint: UIColor(white: 1, alpha: CGFloat(a)), texture: nil)
                mat.blending = .transparent(opacity: 1.0)
                me.model?.materials = [mat]
                e.components[WhiteoutComponent.self] = c
            }
        }
    }

    // Inward white sphere just inside all content; alpha 0 until a jump flashes it (§7b).
    @MainActor
    static func makeEntity() -> ModelEntity {
        var mat = UnlitMaterial()
        mat.color = .init(tint: UIColor(white: 1, alpha: 0), texture: nil)
        mat.blending = .transparent(opacity: 1.0)
        let e = ModelEntity(mesh: .generateSphere(radius: 1.5), materials: [mat])
        e.name = "Whiteout"
        e.scale.z = -1   // render the inside
        e.components.set(WhiteoutComponent())
        return e
    }
}
