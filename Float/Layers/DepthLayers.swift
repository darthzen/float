import RealityKit
import UIKit
import simd

// L1 — §4. Inward sphere, unlit hi-res equirectangular. Effectively at infinity.
enum FarBackdrop {
    // Equirect starfield in the app bundle (NASA SVS Deep Star Maps 2020, public
    // domain — see Resources/Textures/CREDITS.md). ASTC swap is a later step (§4).
    static let textureName = "deep_star_map_8k"

    @MainActor
    static func make(gen: EnvironmentGenerator) -> Entity {
        let mesh = MeshResource.generateSphere(radius: 1000)
        var material = UnlitMaterial()
        material.color = .init(tint: .init(white: 0.01, alpha: 1.0), texture: nil)  // near-black void until the texture loads
        let e = ModelEntity(mesh: mesh, materials: [material])
        e.name = "L1_Backdrop"
        e.scale.z = -1  // flip winding so the inside surface renders

        // Load the equirect asynchronously and swap it in (keeps make() sync so
        // SceneBuilder stays synchronous; backdrop starts black then fills in).
        Task { @MainActor in
            guard let tex = try? await TextureResource(named: textureName) else {
                print("[Float] L1 backdrop texture '\(textureName)' not found — staying void")
                return
            }
            var lit = UnlitMaterial()
            lit.color = .init(tint: .white, texture: .init(tex))  // show equirect at full value
            e.model?.materials = [lit]
        }
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
    // §7 L2 fallback (§10). Soft NOISE-modulated billboard sprites read as wispy gas;
    // clean radial dots read as discs and solid spheres as blobs, so both are gone.
    // Palette sampled from real Webb/Hubble nebulae (Pillars/Carina/Lagoon) — muted
    // blues + dusty rust/tan, not saturated candy colors (see CREDITS.md).
    @MainActor
    static func make(gen: EnvironmentGenerator) -> Entity {
        let e = Entity(); e.name = "L2_Nebula_Particles"
        var rng = gen.nebulaStream()

        // A few fractal-noise sprite variants so overlapping clouds don't look cloned.
        let sprites = (0..<4).compactMap { _ in makeSpriteTexture(&rng) }
        guard !sprites.isEmpty else {
            print("[Float] L2 nebula: sprite generation failed — empty nebula")
            return e
        }

        let palette: [UIColor] = [
            UIColor(red: 0.08, green: 0.17, blue: 0.32, alpha: 1),  // deep blue
            UIColor(red: 0.22, green: 0.29, blue: 0.43, alpha: 1),  // steel blue
            UIColor(red: 0.16, green: 0.30, blue: 0.53, alpha: 1),  // blue
            UIColor(red: 0.52, green: 0.30, blue: 0.23, alpha: 1),  // dusty rust
            UIColor(red: 0.69, green: 0.47, blue: 0.35, alpha: 1),  // warm tan
            UIColor(red: 0.20, green: 0.20, blue: 0.26, alpha: 1),  // muted purple
            UIColor(red: 0.37, green: 0.43, blue: 0.56, alpha: 1)   // lavender-grey
        ]

        // Depth shells give volumetric self-parallax; many small, low-alpha wisps
        // accumulate into continuous haze rather than a few giant discs (§2/§3).
        let depthShells: [Float] = [15, 28, 45, 68, 95, 120]
        for depth in depthShells {
            for _ in 0..<4 {                                   // 4 cluster centers per shell
                let azimuth = 2.0 * Float.pi * rng.unit()
                let elevation = (rng.unit() - 0.5) * 0.9
                let cx = depth * cos(elevation) * cos(azimuth)
                let cy = depth * sin(elevation)
                let cz = depth * cos(elevation) * sin(azimuth)
                let clusterColor = palette[Int(rng.unit() * Float(palette.count)) % palette.count]

                // Shared cluster-facing orientation: keeping every plane in a cluster
                // PARALLEL stops them intersecting each other — crossed transparent quads
                // render a hard seam line, which is the "sharp lines inside" artifact.
                let cForward = normalize(SIMD3<Float>(-cx, -cy, -cz))
                let cWorldUp: SIMD3<Float> = abs(cForward.y) > 0.999 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
                var cRight = cross(cWorldUp, cForward)
                if length(cRight) < 1e-4 { cRight = SIMD3<Float>(1, 0, 0) }
                cRight = normalize(cRight)
                let clusterFace = simd_quatf(simd_float3x3(columns: (cRight, cross(cForward, cRight), cForward)))

                let count = 10 + Int(rng.unit() * 6)           // 10..15 planes per cluster
                for _ in 0..<count {
                    let spread = depth * (0.08 + 0.14 * rng.unit())
                    let ox = spread * (rng.unit() + rng.unit() + rng.unit() - 1.5)  // soft gaussian-ish
                    let oy = spread * (rng.unit() + rng.unit() + rng.unit() - 1.5)
                    let oz = spread * (rng.unit() + rng.unit() + rng.unit() - 1.5)

                    let planeSize = depth * (0.10 + 0.20 * rng.unit())   // smaller than v1
                    let alpha = 0.04 + rng.unit() * 0.07                 // low; overlaps build density
                    let sprite = sprites[Int(rng.unit() * Float(sprites.count)) % sprites.count]

                    let plane = ModelEntity(
                        mesh: MeshResource.generatePlane(width: planeSize, height: planeSize),
                        materials: [makeMaterial(clusterColor, alpha, sprite)]
                    )
                    plane.position = SIMD3<Float>(cx + ox, cy + oy, cz + oz)

                    // All planes share the cluster orientation (parallel → no intersections);
                    // roll about the shared normal keeps them coplanar while varying the sprite.
                    // Viewer never translates (§9), so cluster-facing ≈ viewer-facing.
                    let roll = simd_quatf(angle: 2.0 * Float.pi * rng.unit(), axis: cForward)
                    plane.orientation = roll * clusterFace

                    e.addChild(plane)
                }
            }
        }

        return e
    }

    // Procedural 256² sprite: quadratic radial falloff × fractal value-noise, so each
    // sprite is an irregular gas wisp, not a clean disc. Deterministic from rng.
    @MainActor
    private static func makeSpriteTexture(_ rng: inout SeededRandom) -> TextureResource? {
        let n = 256
        let noise = fractalNoise(n: n, rng: &rng)              // normalized 0...1
        let byteCount = n * n * 4
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 1)
        defer { buffer.deallocate() }
        let px = buffer.bindMemory(to: UInt8.self, capacity: byteCount)
        for y in 0..<n {
            for x in 0..<n {
                let dx = (Float(x) + 0.5) / Float(n) * 2 - 1
                let dy = (Float(y) + 0.5) / Float(n) * 2 - 1
                let f = max(0, 1 - sqrt(dx * dx + dy * dy))
                let radial = f * f
                var a = radial * (0.35 + 0.9 * noise[y * n + x])   // wisps, with a soft floor
                if radial < 0.002 { a = 0 }
                a = min(max(a, 0), 1)
                let i = (y * n + x) * 4
                px[i] = 255; px[i + 1] = 255; px[i + 2] = 255       // white; tint shows through
                px[i + 3] = UInt8(a * 255)
            }
        }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bmp = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.last.rawValue
        guard let cg = CGImage(
            width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: n * 4, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: bmp),
            provider: CGDataProvider(data: Data(bytesNoCopy: px, count: byteCount, deallocator: .none) as CFData)!,
            decode: nil, shouldInterpolate: true, intent: .defaultIntent
        ) else { return nil }
        return try? TextureResource.generate(from: cg, withName: "nebula_sprite", options: .init(semantic: .color))
    }

    // 5-octave value noise (seeded grid + bilinear), summed and normalized to 0...1.
    @MainActor
    private static func fractalNoise(n: Int, rng: inout SeededRandom) -> [Float] {
        var acc = [Float](repeating: 0, count: n * n)
        var amp: Float = 1
        var grid = 4
        for _ in 0..<5 {
            let g = grid
            let stride = g + 1
            var vals = [Float](repeating: 0, count: stride * stride)
            for i in 0..<vals.count { vals[i] = rng.unit() }
            for y in 0..<n {
                let fy = (Float(y) + 0.5) / Float(n) * Float(g)
                let y0 = min(Int(fy), g - 1)
                let ty = fy - Float(y0)
                for x in 0..<n {
                    let fx = (Float(x) + 0.5) / Float(n) * Float(g)
                    let x0 = min(Int(fx), g - 1)
                    let tx = fx - Float(x0)
                    let a = vals[y0 * stride + x0]
                    let b = vals[y0 * stride + x0 + 1]
                    let c = vals[(y0 + 1) * stride + x0]
                    let d = vals[(y0 + 1) * stride + x0 + 1]
                    let top = a + (b - a) * tx
                    let bot = c + (d - c) * tx
                    acc[y * n + x] += amp * (top + (bot - top) * ty)
                }
            }
            amp *= 0.5; grid *= 2
        }
        var lo: Float = .greatestFiniteMagnitude, hi: Float = -.greatestFiniteMagnitude
        for v in acc { lo = min(lo, v); hi = max(hi, v) }
        let range = max(hi - lo, 1e-5)
        for i in 0..<acc.count { acc[i] = (acc[i] - lo) / range }
        return acc
    }

    @MainActor
    private static func makeMaterial(_ color: UIColor, _ alpha: Float, _ sprite: TextureResource) -> UnlitMaterial {
        var m = UnlitMaterial()
        // Full-alpha tint; the sprite's alpha channel shapes the wisp.
        m.color = .init(tint: color, texture: .init(sprite))
        // Per-plane opacity < 1 forces the TRANSPARENT draw pass, so planes don't write
        // depth and can't occlude the clouds behind them — opacity == 1.0 was being
        // treated as opaque (depth-writing), which cut hard-edged notches into clouds.
        // Never set opacityThreshold either — it triggers dithered alpha-masking.
        m.blending = .transparent(opacity: .init(floatLiteral: alpha))
        return m
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
    // 0 comets, 0 meteors — phenomena disabled for M2 star/nebula tuning.
    static let cometCount = 0
    static let meteorCount = 0

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
