import RealityKit
import simd
import Foundation

// L1 — §4. Inward sphere, unlit hi-res equirectangular. Effectively at infinity.
enum FarBackdrop {
    static func make(gen: EnvironmentGenerator) -> Entity {
        let e = Entity(); e.name = "L1_Backdrop"
        // TODO: giant inward sphere (radius ~1000 m), UnlitMaterial with equirect/cubemap
        //       texture; scale.z = -1 to face inward; ASTC-compressed asset (§4).
        return e
    }
}

// L3 — the depth workhorse. Thousands of points across ~2–200 m for real parallax (§3).
enum StarVolume {
    static func make(gen: EnvironmentGenerator) -> Entity {
        let e = Entity(); e.name = "L3_StarVolume"
        let base = ModelEntity(mesh: .generateSphere(radius: 0.02), materials: [UnlitMaterial(color: .white)])
        var rng = gen.starStream()
        let count = min(1200, max(200, Int(1200 * gen.config.starDensity)))
        for _ in 0..<count {
            let u = Double(rng.unit())
            let bias = u * u
            let r = 2.0 + 198.0 * bias
            let theta = 2.0 * Double.pi * Double(rng.unit())
            let phi = acos(2.0 * Double(rng.unit()) - 1.0)
            let px = r * sin(phi) * cos(theta)
            let py = r * sin(phi) * sin(theta)
            let pz = r * cos(phi)
            let sz = max(0.3, 3.0 * (1.0 - r / 220.0))
            let s = base.clone(recursive: false)
            s.position = SIMD3<Float>(Float(px), Float(py), Float(pz))
            s.scale = SIMD3<Float>(repeating: Float(sz))
            e.addChild(s)
        }
        return e
    }
}

// L2 — nebula. Swappable backend: Gaussian splats (v27) or particle fallback (§10).
protocol NebulaBackendRenderer { static func make(gen: EnvironmentGenerator) -> Entity }

enum NebulaVolume {
    static func make(gen: EnvironmentGenerator) -> Entity {
        switch gen.config.nebulaBackend {
        case .splat:     return SplatNebula.make(gen: gen)
        case .particles: return ParticleNebula.make(gen: gen)
        }
    }
}

enum SplatNebula: NebulaBackendRenderer {
    static func make(gen: EnvironmentGenerator) -> Entity {
        let e = Entity(); e.name = "L2_Nebula_Splat"
        // TODO: native RealityKit Gaussian splat entity (v27). Animate palette via
        //       ShaderGraph params keyed off clock.simTime (§5).
        return e
    }
}

enum ParticleNebula: NebulaBackendRenderer {
    static func make(gen: EnvironmentGenerator) -> Entity {
        let e = Entity(); e.name = "L2_Nebula_Particles"
        // TODO: additive soft-particle clouds + a few billboard sheets (fallback §10).
        return e
    }
}

// L4 — §6. Comet / meteor spawner. Deterministic option is an open decision (§11 #13).
enum PhenomenaSpawner {
    static func make(gen: EnvironmentGenerator) -> Entity {
        let e = Entity(); e.name = "L4_Phenomena"
        // TODO: interval spawner scaled by timeScale; particle-trail comets, meteor streaks.
        //       Keep phenomena mostly beyond ~5 m (§6, comfort).
        return e
    }
}
