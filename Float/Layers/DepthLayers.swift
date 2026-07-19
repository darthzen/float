import RealityKit
import simd

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
        var rng = gen.starStream()
        // TODO: distribute N points in a 3D shell with density falloff (NOT one radius).
        //       Prefer LowLevelMesh instanced points; vary brightness/size by distance.
        //       Keep meaningful structure inside ~50 m for stereo disparity (§2).
        _ = rng.next()
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
