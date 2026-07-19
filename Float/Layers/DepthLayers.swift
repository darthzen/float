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

            // NOTE: per-star scale twinkle removed — 3000 component writes/frame caused
            // CPU hitches visible as motion stutter. Revisit with a shader param in M9.

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

        let starCount = 7000
        let minRadius: Float = 2.0
        let maxRadius: Float = 200.0
        let coreMesh = MeshResource.generateSphere(radius: 0.009)
        let haloMesh = MeshResource.generateSphere(radius: 0.012)

        // All core materials use alpha:1.0 — reduced alpha on sub-pixel geometry causes
        // dithering artifacts at 90Hz that look like rapid blinking. Dim via RGB instead.
        let starMaterials: [UnlitMaterial] = [
            UnlitMaterial(color: UIColor(red: 0.80, green: 0.90, blue: 1.00, alpha: 1.0)),  // bright blue-white
            UnlitMaterial(color: UIColor(red: 0.44, green: 0.50, blue: 0.55, alpha: 1.0)),  // dim blue-white
            UnlitMaterial(color: UIColor(red: 0.24, green: 0.28, blue: 0.32, alpha: 1.0)),  // very dim blue-white
            UnlitMaterial(color: UIColor(white: 1.00, alpha: 1.0)),                         // bright white
            UnlitMaterial(color: UIColor(white: 0.55, alpha: 1.0)),                         // dim white
            UnlitMaterial(color: UIColor(red: 1.00, green: 0.95, blue: 0.75, alpha: 1.0)),  // warm white
            UnlitMaterial(color: UIColor(red: 0.70, green: 0.60, blue: 0.39, alpha: 1.0)),  // dim yellow-white
            UnlitMaterial(color: UIColor(red: 0.90, green: 0.63, blue: 0.36, alpha: 1.0))   // orange
        ]

        let haloMaterials: [UnlitMaterial] = [
            UnlitMaterial(color: UIColor(red: 0.80, green: 0.90, blue: 1.00, alpha: 0.20)),  // blue glow
            UnlitMaterial(color: UIColor(white: 1.00, alpha: 0.16))                          // white glow
        ]

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
            let coreScale: Float = 0.40 + distFraction * 0.40   // near=0.40, far=0.80

            let matIndex = Int(rng.unit() * 8.0) % 8
            let star = ModelEntity(mesh: coreMesh, materials: [starMaterials[matIndex]])
            star.position = SIMD3<Float>(x, y, z)
            star.scale = SIMD3<Float>(repeating: coreScale)
            star.components.set(StarComponent(phase: rng.unit() * 2 * Float.pi, baseScale: coreScale))

            // §M2 near-field halo: glow sphere makes close stars read as light sources, not geometry
            if radius < 15.0 {
                let haloMatIndex = matIndex < 4 ? 0 : 1
                let halo = ModelEntity(mesh: haloMesh, materials: [haloMaterials[haloMatIndex]])
                halo.scale = SIMD3<Float>(repeating: coreScale * 2.0)
                star.addChild(halo)
            }

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

// L4 — §6. Comet / meteor spawner. Deterministic option is open (§11 #13); free-running for M2.
struct PhenomenonComponent: Component {
    enum Kind { case comet, meteor }
    var kind: Kind
    var index: Int                  // pool slot, used to vary trajectory on each lap
    var startPos: SIMD3<Float>
    var direction: SIMD3<Float>     // normalized travel direction
    var speed: Float                // m per simTime-second
    var startSimTime: Double
    var lap: Int = 0                // increments on each respawn for trajectory variation
}

struct PhenomenaSystem: System {
    static let clockQuery = EntityQuery(where: .has(ClockComponent.self))
    static let phenQuery  = EntityQuery(where: .has(PhenomenonComponent.self))
    // Phenomena travel 160 m per lap before respawning.
    static let travelDistance: Float = 160

    init(scene: Scene) {}

    func update(context: SceneUpdateContext) {
        MainActor.assumeIsolated {
            var simTime: Double = 0
            for e in context.entities(matching: Self.clockQuery, updatingSystemWhen: .rendering) {
                if let c = e.components[ClockComponent.self] { simTime = c.clock.simTime; break }
            }

            for entity in context.entities(matching: Self.phenQuery, updatingSystemWhen: .rendering) {
                guard var comp = entity.components[PhenomenonComponent.self] else { continue }
                let traveled = comp.speed * Float(simTime - comp.startSimTime)

                if traveled >= Self.travelDistance {
                    comp.lap += 1
                    comp.startSimTime = simTime
                    let (pos, dir) = Self.trajectory(index: comp.index, lap: comp.lap)
                    comp.startPos = pos
                    comp.direction = dir
                    Self.orient(entity: entity, direction: dir)
                    entity.components[PhenomenonComponent.self] = comp
                } else {
                    entity.position = comp.startPos + comp.direction * traveled
                }
            }
        }
    }

    // Deterministic trajectory from (index, lap) using golden-angle distribution.
    static func trajectory(index: Int, lap: Int) -> (SIMD3<Float>, SIMD3<Float>) {
        let seed = Float(index * 7 + lap * 13 + 1)
        let azimuth = seed * 2.39996         // golden angle gives good sky coverage
        let elevation = sin(seed * 1.618) * 0.5
        let r: Float = 100 + sin(seed * 3.7) * 30   // 70–130 m from origin — far enough that box geometry isn't obvious
        let cosEl = cos(elevation)
        let startPos = SIMD3<Float>(r * cosEl * cos(azimuth),
                                    r * sin(elevation),
                                    r * cosEl * sin(azimuth))
        // Direction roughly tangential to the sphere so streaks cross the sky, not head-on.
        let radial = normalize(startPos)
        let worldUp = SIMD3<Float>(0, 1, 0)
        let tangent = normalize(cross(worldUp, radial))
        let drift = sin(seed * 0.7) * 0.3
        let direction = normalize(tangent + SIMD3<Float>(0, drift, 0))
        return (startPos, direction)
    }

    // Align entity's local Z axis with direction so the streak points along travel.
    @MainActor
    static func orient(entity: Entity, direction: SIMD3<Float>) {
        let fwd = normalize(direction)
        let worldUp: SIMD3<Float> = abs(fwd.y) < 0.99 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
        let right = normalize(cross(worldUp, fwd))
        let up = cross(fwd, right)
        entity.orientation = simd_quatf(simd_float3x3(columns: (right, up, fwd)))
    }
}

enum PhenomenaSpawner {
    // 0 comets (removed — too distracting at M2) + 5 meteors.
    static let cometCount = 0
    static let meteorCount = 5

    @MainActor
    static func make(gen: EnvironmentGenerator) -> Entity {
        let e = Entity(); e.name = "L4_Phenomena"
        var rng = gen.phenomenaStream()

        // Comet: bright yellow-white head + long tail, slow drift.
        let cometMesh = MeshResource.generateBox(width: 0.04, height: 0.04, depth: 4.0)
        var cometMat = UnlitMaterial()
        cometMat.color = .init(tint: .init(red: 1.0, green: 0.95, blue: 0.7, alpha: 1.0), texture: nil)

        for i in 0..<cometCount {
            let (pos, dir) = PhenomenaSystem.trajectory(index: i, lap: 0)
            let comet = ModelEntity(mesh: cometMesh, materials: [cometMat])
            comet.position = pos
            comet.components.set(PhenomenonComponent(
                kind: .comet, index: i, startPos: pos, direction: dir,
                speed: 4 + rng.unit() * 3,   // 4–7 m/simSec
                startSimTime: Double(rng.unit() * 20)   // stagger starts
            ))
            PhenomenaSystem.orient(entity: comet, direction: dir)
            e.addChild(comet)
        }

        // Meteor: short bright blue-white streak, fast.
        let meteorMesh = MeshResource.generateBox(width: 0.02, height: 0.02, depth: 1.2)
        var meteorMat = UnlitMaterial()
        meteorMat.color = .init(tint: .init(red: 0.8, green: 0.9, blue: 1.0, alpha: 1.0), texture: nil)

        for i in 0..<meteorCount {
            let idx = cometCount + i
            let (pos, dir) = PhenomenaSystem.trajectory(index: idx, lap: 0)
            let meteor = ModelEntity(mesh: meteorMesh, materials: [meteorMat])
            meteor.position = pos
            meteor.components.set(PhenomenonComponent(
                kind: .meteor, index: idx, startPos: pos, direction: dir,
                speed: 18 + rng.unit() * 12,  // 18–30 m/simSec
                startSimTime: Double(rng.unit() * 10)   // stagger starts
            ))
            PhenomenaSystem.orient(entity: meteor, direction: dir)
            e.addChild(meteor)
        }

        return e
    }
}
