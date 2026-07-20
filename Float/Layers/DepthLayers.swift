import RealityKit
import UIKit
import simd
import Metal   // MTLAttributeFormat for GaussianSplatResource buffer descriptors (§10)

// L1 — §4. Inward sphere, unlit hi-res equirectangular. Effectively at infinity.
enum FarBackdrop {
    // Base equirect panoramas in the bundle — NASA SVS Deep Star Maps (public domain) plus
    // Shutterstock RF space skies (see CREDITS.md). config.backdrop picks the base; per-seed
    // rotation + a subtle color wash vary it further so jumps rarely repeat the same sky (§7a).
    static let textureNames = [
        "deep_star_map_8k", "dual_nebula", "blue_filaments", "teal_orange", "dark_dust", "pale_haze"
    ]

    // §7a — how much real nebulosity/structure each panorama already carries (0 = near-black
    // star field, 1 = nebula-filled sky). MEASURED from the panoramas (blurred-luminance mean
    // + large-scale variation + non-black coverage), not eyeballed. Index-aligned with
    // textureNames. Drives generated-nebula density down (below) so our procedural gas doesn't
    // pile onto — and thereby give away — an already-busy real sky.
    static let busyness: [Float] = [0.00, 0.80, 0.89, 0.65, 0.28, 0.93]

    // Multiplier applied to a config's nebula density for a given backdrop: a quiet sky keeps
    // the full range, a busy sky gets a whisper. The freed-up depth cue is the (unchanged,
    // dense) L3 star field showing through more clearly — see AppModel.applyNewEnvironment.
    static func nebulaScale(forBackdrop index: Int) -> Float {
        let n = textureNames.count
        let b = busyness[((index % n) + n) % n]
        return 1.0 - 0.85 * b            // busy=0 → 1.0, busy=0.93 → ~0.21
    }

    @MainActor
    static func make(gen: EnvironmentGenerator) -> Entity {
        let mesh = MeshResource.generateSphere(radius: 1000)
        var material = UnlitMaterial()
        material.color = .init(tint: .init(white: 0.01, alpha: 1.0), texture: nil)  // near-black void until the texture loads
        let e = ModelEntity(mesh: mesh, materials: [material])
        e.name = "L1_Backdrop"
        e.scale.z = -1  // flip winding so the inside surface renders
        reskin(e, gen: gen)
        return e
    }

    // Pick the panorama, orientation, and tint for this environment and apply them to an
    // existing backdrop sphere — used both at build time and on a jump (§7b). Loads on
    // demand (no cache): replacing the material drops the old texture, so only ~1 8K
    // panorama is resident at a time (6 cached would blow the GPU budget).
    @MainActor
    static func reskin(_ e: ModelEntity, gen: EnvironmentGenerator) {
        var rng = gen.backdropStream()
        let idx = ((gen.config.backdrop % textureNames.count) + textureNames.count) % textureNames.count
        let name = textureNames[idx]

        // Per-seed orientation: uniform-random rotation so the sky lands differently.
        let pi = Float.pi
        let u1 = rng.unit(), u2 = rng.unit(), u3 = rng.unit()
        e.orientation = simd_quatf(vector: SIMD4<Float>(
            sqrt(1 - u1) * sin(2 * pi * u2), sqrt(1 - u1) * cos(2 * pi * u2),
            sqrt(u1) * sin(2 * pi * u3),     sqrt(u1) * cos(2 * pi * u3)))

        // Subtle per-seed color wash (mostly white, slight cast).
        let tint = UIColor(red: CGFloat(0.82 + 0.18 * rng.unit()),
                           green: CGFloat(0.82 + 0.18 * rng.unit()),
                           blue: CGFloat(0.82 + 0.18 * rng.unit()), alpha: 1)

        Task { @MainActor in
            guard let tex = try? await TextureResource(named: name) else {
                print("[Float] L1 backdrop texture '\(name)' not found")
                return
            }
            var lit = UnlitMaterial()
            lit.color = .init(tint: tint, texture: .init(tex))
            e.model?.materials = [lit]
        }
    }
}

// §7b whiteout — a brief full-view white flash that masks the environment swap. Driven by
// a System (runs every render frame, unlike the Task tweens that proved unreliable here).
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

// L3 — the depth workhorse. Thousands of points across ~25–260 m for real parallax (§3).
// Field pushed back off the viewer so it reads clearly behind the hero bodies (~90 m)
// instead of intermingling with them, which flattened the whole scene.
enum StarVolume {
    @MainActor
    static func make(gen: EnvironmentGenerator) -> Entity {
        let e = Entity(); e.name = "L3_StarVolume"
        e.components.set(StarVolumeComponent())
        var rng = gen.starStream()

        let starCount = 7000
        let minRadius: Float = 25.0
        let maxRadius: Float = 260.0
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

            // §M2 near-field halo: glow sphere makes the nearest stars read as light sources,
            // not geometry. Threshold tracks the new 25 m near boundary (was 15 m at 2 m min).
            if radius < 45.0 {
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

// §7a — distinct nebula palettes; config.nebulaPalette picks one per environment so each
// jump lands in a differently-colored nebula. Linear RGB, evoking real nebula types.
enum NebulaPalettes {
    static let sets: [[SIMD3<Float>]] = [
        // 0 — blue reflection + dusty rust (Pleiades / Carina-like)
        [[0.08, 0.17, 0.32], [0.22, 0.29, 0.43], [0.16, 0.30, 0.53], [0.52, 0.30, 0.23], [0.69, 0.47, 0.35], [0.20, 0.20, 0.26], [0.37, 0.43, 0.56]],
        // 1 — red emission / H-alpha (Eagle / Lagoon-like)
        [[0.55, 0.14, 0.18], [0.72, 0.24, 0.28], [0.60, 0.20, 0.30], [0.45, 0.16, 0.22], [0.80, 0.42, 0.35], [0.30, 0.12, 0.16], [0.66, 0.30, 0.28]],
        // 2 — teal / planetary (OIII, Helix-like)
        [[0.10, 0.42, 0.44], [0.16, 0.55, 0.52], [0.20, 0.45, 0.60], [0.30, 0.62, 0.55], [0.12, 0.35, 0.50], [0.40, 0.66, 0.60], [0.08, 0.30, 0.40]],
        // 3 — violet / magenta (Trifid-like)
        [[0.38, 0.18, 0.48], [0.50, 0.24, 0.55], [0.55, 0.20, 0.40], [0.30, 0.16, 0.45], [0.62, 0.34, 0.58], [0.22, 0.14, 0.36], [0.48, 0.26, 0.50]],
        // 4 — gold / amber dust (dusty star nursery)
        [[0.55, 0.40, 0.20], [0.70, 0.52, 0.28], [0.62, 0.44, 0.24], [0.45, 0.32, 0.18], [0.78, 0.60, 0.36], [0.36, 0.26, 0.16], [0.68, 0.48, 0.26]],
        // 5 — cool cyan-white (faint reflection)
        [[0.30, 0.42, 0.52], [0.42, 0.54, 0.64], [0.24, 0.36, 0.48], [0.50, 0.60, 0.68], [0.34, 0.46, 0.56], [0.20, 0.30, 0.42], [0.46, 0.56, 0.66]],
    ]

    static func palette(_ index: Int) -> [SIMD3<Float>] {
        sets[((index % sets.count) + sets.count) % sets.count]
    }
}

// Procedurally-generated Gaussian-splat data for the nebula. Pure math, deterministic
// from the seed — no RealityKit/Metal — so it compiles everywhere (device + sim).
struct NebulaSplatData {
    var positions: [SIMD3<Float>]   // meters, world space around origin
    var scales:    [SIMD3<Float>]   // per-axis Gaussian std-dev in meters (anisotropic)
    var rotations: [SIMD4<Float>]   // unit quaternion packed (x, y, z, w)
    var opacities: [Float]          // 0...1
    var colors:    [SIMD3<Float>]   // linear RGB 0...1
}

enum SplatNebula: NebulaBackendRenderer {
    @MainActor
    static func make(gen: EnvironmentGenerator) -> Entity {
        #if targetEnvironment(simulator)
        // Native Gaussian splats aren't in the visionOS simulator SDK — fall back to
        // the particle nebula in the sim; real splats render on device (§10).
        return ParticleNebula.make(gen: gen)
        #else
        let e = Entity(); e.name = "L2_Nebula_Splat"
        let data = generateSplatData(gen: gen)
        guard !data.positions.isEmpty else { return e }
        do {
            e.components.set(try makeSplatComponent(data))
        } catch {
            print("[Float] L2 splat build failed (\(error)) — falling back to particles")
            return ParticleNebula.make(gen: gen)
        }
        return e
        #endif
    }

    // §7 L2. Distribute anisotropic Gaussians across depth shells, clustered and
    // palette-colored (sampled from real Webb/Hubble nebulae — see CREDITS.md).
    @MainActor
    static func generateSplatData(gen: EnvironmentGenerator) -> NebulaSplatData {
        var rng = gen.nebulaStream()
        let pi = Float.pi

        // Far shells: near clouds at 15 m parallaxed way too hard as true 3D splats;
        // real nebulae are near-infinite, so push them out for gentle parallax (§9 comfort).
        // Whole field moved back again so the nebula sits clearly behind the hero bodies
        // and reaches toward the 1000 m backdrop instead of reading flat.
        let depthShells: [Float] = [120, 170, 230, 300, 390, 500]
        let palette = NebulaPalettes.palette(gen.config.nebulaPalette)   // §7a per-environment color

        var positions: [SIMD3<Float>] = []
        var scales: [SIMD3<Float>] = []
        var rotations: [SIMD4<Float>] = []
        var opacities: [Float] = []
        var colors: [SIMD3<Float>] = []

        for depth in depthShells {
            for _ in 0..<3 {                                   // 3 clusters/shell
                // §3 bias clusters toward the viewer's initial forward (-Z) so the busy nebula
                // tends to land in front on entry, not behind. Soft — some still go behind; one
                // rng draw keeps the seed sequence. Flip `front`'s sign if it biases backward.
                let front: Float = -pi / 2
                let a = 2 * rng.unit() - 1                      // [-1, 1)
                let azimuth = front + (a * abs(a)) * pi         // concentrated near front
                let elevation = (rng.unit() - 0.5) * 0.9
                let cx = depth * cos(elevation) * cos(azimuth)
                let cy = depth * sin(elevation)
                let cz = depth * cos(elevation) * sin(azimuth)
                let clusterColor = palette[Int(rng.unit() * Float(palette.count)) % palette.count]

                let count = Int(Float(150 + Int(rng.unit() * 100)) * (0.6 + gen.config.nebulaDensity))  // §7a density
                for _ in 0..<count {
                    let spread = depth * (0.06 + 0.10 * rng.unit())
                    let ox = spread * (rng.unit() + rng.unit() + rng.unit() - 1.5)
                    let oy = spread * (rng.unit() + rng.unit() + rng.unit() - 1.5)
                    let oz = spread * (rng.unit() + rng.unit() + rng.unit() - 1.5)
                    positions.append(SIMD3<Float>(cx + ox, cy + oy, cz + oz))

                    let baseSize = depth * (0.003 + 0.006 * rng.unit())   // moderate (size doesn't affect the jitter)
                    let elongation = 1 + 2 * rng.unit()
                    let scaleZ = baseSize * (0.6 + 0.4 * rng.unit())
                    scales.append(SIMD3<Float>(baseSize * elongation, baseSize, scaleZ))

                    // uniform-random unit quaternion (x, y, z, w)
                    let u1 = rng.unit(), u2 = rng.unit(), u3 = rng.unit()
                    rotations.append(SIMD4<Float>(
                        sqrt(1 - u1) * sin(2 * pi * u2),
                        sqrt(1 - u1) * cos(2 * pi * u2),
                        sqrt(u1) * sin(2 * pi * u3),
                        sqrt(u1) * cos(2 * pi * u3)
                    ))

                    opacities.append(0.06 + 0.14 * rng.unit())

                    let v = 0.8 + 0.4 * rng.unit()
                    colors.append(SIMD3<Float>(min(1, clusterColor.x * v),
                                               min(1, clusterColor.y * v),
                                               min(1, clusterColor.z * v)))
                }
            }
        }
        return NebulaSplatData(positions: positions, scales: scales,
                               rotations: rotations, opacities: opacities, colors: colors)
    }

    #if !targetEnvironment(simulator)
    // Pack the generated arrays into the native GaussianSplatResource buffer layout (vOS27).
    @MainActor
    private static func makeSplatComponent(_ d: NebulaSplatData) throws -> GaussianSplatComponent {
        let n = d.positions.count
        // SH degree 0 = one DC coefficient per channel. 3DGS convention: dc = (rgb - 0.5) / C0.
        let c0: Float = 0.2820948
        let sh = d.colors.map { ($0 - SIMD3<Float>(repeating: 0.5)) / c0 }

        let stride3 = MemoryLayout<SIMD3<Float>>.stride     // 16 (float3 reads first 12)
        let stride4 = MemoryLayout<SIMD4<Float>>.stride     // 16
        let stride1 = MemoryLayout<Float>.stride            // 4

        let br = try GaussianSplatResource.BufferResource(
            count: n,
            position: .init(buffer: try buffer(d.positions), format: .float3, stride: stride3, offset: 0),
            scale:    .init(buffer: try buffer(d.scales),    format: .float3, stride: stride3, offset: 0),
            rotation: .init(buffer: try buffer(d.rotations), format: .float4, stride: stride4, offset: 0),
            opacity:  .init(buffer: try buffer(d.opacities), format: .float,  stride: stride1, offset: 0),
            sphericalHarmonics: (.init(buffer: try buffer(sh), format: .float3, stride: stride3, offset: 0), .zero)
        )
        let resource = GaussianSplatResource(br)
        // We supply real meters + 0...1 opacity directly, not 3DGS log/logit encodings.
        resource.scaleActivation = .identity
        resource.opacityActivation = .identity
        // NOTE: neither of these fixes the full-surround reprojection jitter on the vOS27
        // beta (ruled out along with distance + splat size — see EnvironmentConfig / the
        // filed FB). Kept as the most sensible settings for when Apple fixes it: tangential
        // projection + radial-distance sorting for an all-directions volume.
        resource.projectionMode = .tangential
        resource.sortingMode = .distance
        return GaussianSplatComponent(resource)
    }

    @MainActor
    private static func buffer<T>(_ array: [T]) throws -> LowLevelBuffer {
        let byteCount = array.count * MemoryLayout<T>.stride
        // LowLevelBuffer capacity must be 16-byte aligned (the float-stride opacity
        // buffer otherwise fails with invalid(bufferCapacity:)). Extra tail bytes are
        // harmless — descriptors read `count` elements at explicit stride.
        let capacity = (byteCount + 15) & ~15
        let buf = try LowLevelBuffer(descriptor: .init(capacity: capacity))
        // Claim the full region BEFORE writing, so the mutable-bytes callback exposes
        // capacity bytes (not the initial bytesUsed == 0) — otherwise the copy below
        // writes out of bounds and corrupts the heap.
        buf.bytesUsed = capacity
        buf.withUnsafeMutableBytes { dst in
            guard let base = dst.baseAddress, dst.count >= byteCount else { return }
            array.withUnsafeBytes { src in
                if let s = src.baseAddress { base.copyMemory(from: s, byteCount: byteCount) }
            }
        }
        return buf
    }
    #endif
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

        let palette = NebulaPalettes.palette(gen.config.nebulaPalette).map {   // §7a per-environment color
            UIColor(red: CGFloat($0.x), green: CGFloat($0.y), blue: CGFloat($0.z), alpha: 1)
        }

        // Depth shells give volumetric self-parallax; many small, low-alpha wisps
        // accumulate into continuous haze rather than a few giant discs (§2/§3).
        // Pushed back off the viewer to match the star field — the near shell no longer
        // crowds the hero bodies, so the haze reads as a distant backdrop, not flat.
        let depthShells: [Float] = [50, 85, 130, 185, 250, 320]
        for depth in depthShells {
            for _ in 0..<4 {                                   // 4 cluster centers per shell
                // §3 bias clusters toward the viewer's initial forward (-Z) — busy nebula tends
                // to land in front on entry, not behind. Soft; one rng draw keeps the sequence.
                // Flip `front`'s sign if it biases backward on device.
                let front: Float = -Float.pi / 2
                let a = 2 * rng.unit() - 1
                let azimuth = front + (a * abs(a)) * Float.pi
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

                let count = Int(Float(22 + Int(rng.unit() * 12)) * (0.6 + gen.config.nebulaDensity))  // §7a density
                for _ in 0..<count {
                    let spread = depth * (0.08 + 0.14 * rng.unit())
                    let ox = spread * (rng.unit() + rng.unit() + rng.unit() - 1.5)  // soft gaussian-ish
                    let oy = spread * (rng.unit() + rng.unit() + rng.unit() - 1.5)
                    let oz = spread * (rng.unit() + rng.unit() + rng.unit() - 1.5)

                    // Scales with depth so far clouds subtend a natural angle, but capped:
                    // planes from *different* clusters aren't parallel, so where big quads
                    // reach across into a neighbouring cluster they interpenetrate and draw
                    // a hard seam — the "sharp lines" artifact. Cap keeps a plane smaller than
                    // the inter-cluster gap. (This is sorted-transparency intersection, NOT the
                    // vOS26 depth break — that one's gone on vOS27; this cap stays regardless.)
                    let planeSize = min(depth * (0.04 + 0.08 * rng.unit()), 10.0)
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
        m.color = .init(tint: color, texture: .init(sprite))
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
