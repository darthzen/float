import RealityKit
import UIKit
import simd

// L1 — §4. Inward sphere, unlit hi-res equirectangular. Effectively at infinity.
enum FarBackdrop {
    @MainActor
    static func make(gen: EnvironmentGenerator) -> Entity {
        let mesh = MeshResource.generateSphere(radius: 1000)
        var material = UnlitMaterial()
        material.color = .init(tint: .init(white: 0.01, alpha: 1.0), texture: nil)  // near-black void
        let e = ModelEntity(mesh: mesh, materials: [material])
        e.name = "L1_Backdrop"
        e.scale.z = -1  // flip winding so the inside surface renders
        return e
    }
}

// Marker so StarAnimationSystem can find and rotate the star volume container via query.
struct StarVolumeComponent: Component {}

// Per-star data for twinkle animation driven by simTime (§5).
struct StarComponent: Component {
    var phase: Float       // random offset in [0, 2π) seeded per-star
    var baseScale: Float   // scale at rest; twinkle multiplies this
}

struct StarAnimationSystem: System {
    static let clockQuery  = EntityQuery(where: .has(ClockComponent.self))
    static let starQuery   = EntityQuery(where: .has(StarComponent.self))
    static let volumeQuery = EntityQuery(where: .has(StarVolumeComponent.self))

    init(scene: Scene) {}

    func update(context: SceneUpdateContext) {
        MainActor.assumeIsolated {
            // Read simTime from the scene-level ClockComponent.
            var simTime: Double = 0
            for entity in context.entities(matching: Self.clockQuery, updatingSystemWhen: .rendering) {
                if let comp = entity.components[ClockComponent.self] {
                    simTime = comp.clock.simTime
                    break
                }
            }

            // Per-star brightness twinkle — pure function of (phase, simTime).
            for entity in context.entities(matching: Self.starQuery, updatingSystemWhen: .rendering) {
                if let comp = entity.components[StarComponent.self] {
                    let twinkle = 1.0 + 0.15 * sin(Float(simTime) * 0.8 + comp.phase)
                    entity.scale = SIMD3<Float>(repeating: comp.baseScale * twinkle)
                }
            }

            // Slow global yaw of the L3 star volume (~0.3°/sec, pure function of simTime).
            for entity in context.entities(matching: Self.volumeQuery, updatingSystemWhen: .rendering) {
                entity.orientation = simd_quatf(angle: Float(simTime) * 0.005,
                                                axis: SIMD3<Float>(0, 1, 0))
            }
        }
    }
}

// L3 — the depth workhorse. Thousands of points across ~2–200 m for real parallax (§3).
enum StarVolume {
    @MainActor
    static func make(gen: EnvironmentGenerator) -> Entity {
        let e = Entity(); e.name = "L3_StarVolume"
        e.components.set(StarVolumeComponent())
        var rng = gen.starStream()

        let starCount = 3000
        let minRadius: Float = 2.0
        let maxRadius: Float = 200.0
        let mesh = MeshResource.generateSphere(radius: 0.01)

        for _ in 0..<starCount {
            // sqrt falloff: denser in the near range where stereo disparity matters most
            let radius = minRadius + (maxRadius - minRadius) * sqrt(rng.unit())

            // uniform spherical direction (Y = up in RealityKit)
            let azimuth = 2.0 * Float.pi * rng.unit()
            let elevation = asin(2.0 * rng.unit() - 1.0)
            let x = radius * cos(elevation) * cos(azimuth)
            let y = radius * sin(elevation)
            let z = radius * cos(elevation) * sin(azimuth)

            let distFraction = (radius - minRadius) / (maxRadius - minRadius)
            let scale = max(0.1, 1.0 - 0.8 * distFraction)

            let star = ModelEntity(mesh: mesh, materials: [UnlitMaterial()])
            star.position = SIMD3<Float>(x, y, z)
            star.scale = SIMD3<Float>(repeating: scale)
            star.components.set(StarComponent(phase: rng.unit() * 2 * Float.pi, baseScale: scale))
            e.addChild(star)
        }

        return e
    }
}

// L2 — nebula. Swappable backend: Gaussian splats (v27) or particle fallback (§10).
protocol NebulaBackendRenderer { @MainActor static func make(gen: EnvironmentGenerator) -> Entity }

enum NebulaVolume {
    @MainActor
    static func make(gen: EnvironmentGenerator) -> Entity {
        switch gen.config.nebulaBackend {
        case .splat:     return SplatNebula.make(gen: gen)
        case .particles: return ParticleNebula.make(gen: gen)
        }
    }
}

enum SplatNebula: NebulaBackendRenderer {
    @MainActor
    static func make(gen: EnvironmentGenerator) -> Entity {
        let e = Entity(); e.name = "L2_Nebula_Splat"
        // TODO: native RealityKit Gaussian splat entity (v27). Animate palette via
        //       ShaderGraph params keyed off clock.simTime (§5).
        return e
    }
}

enum ParticleNebula: NebulaBackendRenderer {
    @MainActor
    static func make(gen: EnvironmentGenerator) -> Entity {
        let e = Entity(); e.name = "L2_Nebula_Particles"
        var rng = gen.nebulaStream()

        // 3 billboard planes per depth shell; multiple shells give volumetric parallax.
        let depthShells: [Float] = [6, 12, 22, 38, 60, 90, 140]

        for depth in depthShells {
            for _ in 0..<3 {
                let azimuth = 2.0 * Float.pi * rng.unit()
                let elevation = (rng.unit() - 0.5) * Float.pi * 0.6
                let x = depth * cos(elevation) * cos(azimuth)
                let y = depth * sin(elevation)
                let z = depth * cos(elevation) * sin(azimuth)

                // Far clouds subtend a similar solid angle to near ones.
                let size = depth * (0.5 + 0.8 * rng.unit())
                let mesh = MeshResource.generatePlane(width: size, depth: size)

                // Cool nebula tint: blues/purples/pinks seeded per cloud.
                let hue = rng.unit()
                let r = Float(0.2 + 0.4 * sin(Double(hue) * .pi))
                let g = Float(0.1 + 0.15 * sin(Double(hue) * .pi * 2 + 1.0))
                let b = Float(0.5 + 0.5 * rng.unit())
                var mat = UnlitMaterial()
                mat.color = .init(tint: .init(red: CGFloat(r),
                                              green: CGFloat(g),
                                              blue: CGFloat(b),
                                              alpha: CGFloat(0.08 + 0.12 * rng.unit())),
                                  texture: nil)

                let cloud = ModelEntity(mesh: mesh, materials: [mat])
                cloud.position = SIMD3<Float>(x, y, z)

                // Orient plane normal toward origin so it faces the viewer.
                let pos = SIMD3<Float>(x, y, z)
                let forward = normalize(-pos)
                let worldUp = SIMD3<Float>(0, 1, 0)
                let right = normalize(cross(worldUp, forward))
                let up = cross(forward, right)
                cloud.orientation = simd_quatf(simd_float3x3(columns: (right, up, forward)))
                e.addChild(cloud)
            }
        }

        return e
    }
}

// L4 — §6. Comet / meteor spawner. Deterministic option is an open decision (§11 #13).
enum PhenomenaSpawner {
    @MainActor
    static func make(gen: EnvironmentGenerator) -> Entity {
        let e = Entity(); e.name = "L4_Phenomena"
        // TODO: interval spawner scaled by timeScale; particle-trail comets, meteor streaks.
        //       Keep phenomena mostly beyond ~5 m (§6, comfort).
        return e
    }
}
