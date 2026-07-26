import RealityKit
import RealityKitContent
import Foundation
import ImageIO
import CoreGraphics

/// Presents a bundled **Apple Spatial** (stereo 360° equirect) still as the immersive
/// environment — the app's sole scene system since the generated L1–L4 pipeline was retired.
/// AppModel selects a sky by `catalog` index (`selectScene` / `randomScene`).
///
/// Rendering: an **inward sphere** at ~infinity (wraps 360°). Two material paths, picked at
/// load time:
///   • STEREO — the `Stereo360` `ShaderGraphMaterial` (a Camera Index Switch selecting per-eye),
///     hand-authored as USD in the RealityKitContent package, with its `LeftEye`/`RightEye`
///     texture parameters set at runtime from the HEIC's two eyes (CGImage index 0 = left,
///     1 = right).
///   • MONO fallback — primary eye on an UnlitMaterial, if the material or an eye can't load.
/// (visionOS 26 `ImagePresentationComponent` was tried first but renders a spatial photo as a
/// flat floating panel, not a surround, so it's wrong for an equirect environment.)
enum SpatialImageEnvironment {
    /// One selectable sky. All are 2-image stereo HEICs in Resources/Textures/Backdrop
    /// (see CREDITS.md) that render through the `Stereo360` material — per-eye stereo on
    /// device, mono in the simulator (which can't show two eyes). `spatial_*` are the
    /// pipeline's own conversions (mono → DA V2 / luminance depth → ODS stereo, see
    /// upscale/process_backdrops.py); `imported_spatial_*` are the earlier toolkit exports.
    /// `thumb` is the selector thumbnail in Backdrop/Thumbnails/<name>.jpg.
    struct Scene: Identifiable, Hashable {
        let name: String        // bundle resource name (the HEIC, and the thumbnail stem)
        let title: String       // selector label
        let grounded: Bool      // real horizon (vertigo-mitigation group)
        var id: String { name }
    }

    static let catalog: [Scene] = [
        // ── Grounded (real horizon) ────────────────────────────────────────────
        .init(name: "spatial_rogland_night",   title: "Rogland Desert Night",  grounded: true),
        .init(name: "spatial_dikhololo_night", title: "Dikhololo Night",       grounded: true),
        .init(name: "spatial_paranal_vlt",     title: "Paranal — VLT",         grounded: true),
        .init(name: "spatial_paranal_lasers",  title: "Paranal — Laser Guide", grounded: true),
        .init(name: "spatial_lasilla_arc",     title: "La Silla — Milky Way",  grounded: true),
        .init(name: "spatial_lasilla_airglow", title: "La Silla — Airglow",    grounded: true),
        // ── Deep space (no horizon) ────────────────────────────────────────────
        .init(name: "spatial_deep_star_map",   title: "Deep Star Map",         grounded: false),
        .init(name: "spatial_dual_nebula",     title: "Dual Nebula",           grounded: false),
        .init(name: "spatial_blue_filaments",  title: "Blue Filaments",        grounded: false),
        .init(name: "spatial_teal_orange",     title: "Teal & Orange",         grounded: false),
        .init(name: "spatial_dark_dust",       title: "Dark Dust",             grounded: false),
        .init(name: "spatial_pale_haze",       title: "Pale Haze",             grounded: false),
        // ── Deep-sky masters (gnomonic composite over the Deep Star Map plate,
        //    see upscale/deepsky_pipeline.py; credits in CREDITS.md) ───────────
        .init(name: "spatial_m16_pillars",     title: "Pillars of Creation",   grounded: false),
        .init(name: "spatial_carina_mystic",   title: "Carina — Mystic Mountain", grounded: false),
        .init(name: "spatial_m8_lagoon",       title: "Lagoon Nebula",         grounded: false),
        // The equidistant-wrap A/B (fov 95) lost — the angle read as weird on device.
        .init(name: "spatial_m104_sombrero",   title: "Sombrero Galaxy",       grounded: false),
        .init(name: "spatial_s106_angel",      title: "S106 — Snow Angel",     grounded: false),
        .init(name: "spatial_m106_spiral",     title: "M106 Spiral Galaxy",    grounded: false),
        .init(name: "spatial_ngc4631_whale",   title: "Whale Galaxy",          grounded: false),
        .init(name: "spatial_m31_andromeda",   title: "Andromeda",             grounded: false),
        // ── SPHEREx all-sky maps (native equirect, process_backdrops.py) ──────
        .init(name: "spatial_spherex_stars",   title: "SPHEREx — Stars",       grounded: false),
        .init(name: "spatial_spherex_full",    title: "SPHEREx — Stars + Lines", grounded: false),
        // ── unWISE custom all-sky (built from CDS HiPS at target res —
        //    scripts/fetch_unwise.py + upscale/allsky_rgb.py) ────────────────
        .init(name: "spatial_unwise_allsky",   title: "unWISE — Infrared Sky",  grounded: false),
        // ── ESA/Webb POTM batch (auto-placed by potm_auto_manifest.py; first-guess
        //    framing — nudge fov/exposure in deepsky_auto.json and re-run to tune) ──
        .init(name: "spatial_potm2508a", title: "Dusty wisps round a dusty disc", grounded: false),
        .init(name: "spatial_potm2410a", title: "Edge of the Phantom Galaxy", grounded: false),
        .init(name: "spatial_potm2408a", title: "Peeking into Perseus", grounded: false),
        .init(name: "spatial_potm2405a", title: "Fireworks of stellar starbursts", grounded: false),
        .init(name: "spatial_potm2402a", title: "A galactic treasury", grounded: false),
        .init(name: "spatial_potm2310a", title: "No tricks, just treats", grounded: false),
        .init(name: "spatial_potm2308a", title: "A FEAST for the eyes", grounded: false),
        .init(name: "spatial_potm2307a", title: "The life and times of dust", grounded: false),
        .init(name: "spatial_potm2305a", title: "Webb peers behind bars", grounded: false),
        .init(name: "spatial_potm2301a", title: "A Spiral Amongst Thousands", grounded: false),
        .init(name: "spatial_potm2211a", title: "Galactic Get-Together", grounded: false),
        .init(name: "spatial_potm2210a", title: "Merging Galaxies", grounded: false),
        .init(name: "spatial_potm2208a", title: "Heart of the Phantom Galaxy", grounded: false),
        .init(name: "spatial_potm2207a", title: "Stephan's Quintet", grounded: false),
        .init(name: "spatial_pillarsofcreation_composite", title: "Pillars of Creation (Composite)", grounded: false),
        .init(name: "spatial_carinanebula3", title: "Carina Nebula Jets", grounded: false),
        .init(name: "spatial_weic2615a", title: "Centaurus A", grounded: false),
        .init(name: "spatial_weic2608a", title: "Star-forming regions in M51", grounded: false),
        .init(name: "spatial_weic2520a", title: "Sagittarius B2 (NIRCam)", grounded: false),
        .init(name: "spatial_weic2427a", title: "Sombrero Galaxy (MIRI)", grounded: false),
        .init(name: "spatial_weic2316a", title: "Rho Ophiuchi cloud complex", grounded: false),
        .init(name: "spatial_saturn1", title: "Saturn", grounded: false),
        .init(name: "spatial_bullet-cluster", title: "Bullet Cluster", grounded: false),
        .init(name: "spatial_potm2401b", title: "S1 LMC N79", grounded: false),
        .init(name: "spatial_heic0604a", title: "Messier 82 (Hubble)", grounded: false),
        .init(name: "spatial_weic2520b", title: "Sagittarius B2 (MIRI)", grounded: false),
        .init(name: "spatial_weic2205b", title: "Cosmic Cliffs (Composite)", grounded: false),
        // NOTE: the earlier `imported_spatial_1…5` were dropped — they were the Spatial-Media-
        // Toolkit-Pro exports of these SAME five Shutterstock photos (verified by image match),
        // so the six deep-space entries above already ARE those skies, recreated by our pipeline
        // with the coherence + cos² zenith fixes the pre-baked exports couldn't get.
    ]

    /// Resource names in catalog order — the index space AppModel/`load(index:)` use.
    static var resourceNames: [String] { catalog.map(\.name) }

    // Must match the authored RCP material (see the package README).
    private static let materialSceneName = "Stereo360"          // Stereo360.usda
    private static let materialPrimPath  = "/Root/Stereo360"     // material prim path
    private static let leftParam  = "LeftEye"
    private static let rightParam = "RightEye"

    private static let skyboxName = "ImportedSpatial_Skybox"
    private static let sphereRadius: Float = 1000

    private enum SpatialError: Error { case eyesUnavailable }

    /// The container that holds the current imported sky. Created empty (so visibility toggles
    /// work immediately); populate/swap with `load(index:into:)`.
    @MainActor
    static func makeContainer() -> Entity {
        let e = Entity()
        e.name = "ImportedSpatialEnvironment"
        return e
    }

    /// Swap the container's skybox to `resourceNames[index]`. Tries the stereo material first,
    /// falls back to the mono skybox. Removes the previous sky so cycling doesn't stack spheres.
    @MainActor
    static func load(index: Int, into container: Entity) async {
        guard let sphere = await prepare(index: index) else { return }
        attach(sphere, to: container)
    }

    /// Build the skybox entity WITHOUT attaching it — the expensive half (HEIC decode,
    /// two 12288x6144 texture uploads, the ShaderGraph material) with no scene required.
    ///
    /// Split out so the first sky can be decoded BEFORE the immersive space opens. The old
    /// order was: open the space, then start loading into it, which left a real window where
    /// the space existed with nothing in it — on device that read as "immersion starts, but
    /// it's just flat black". Entities don't need a scene to exist, so the wait can happen
    /// while the launcher/splash is still the only thing on screen, and the space can then
    /// come up already populated.
    @MainActor
    static func prepare(index: Int) async -> ModelEntity? {
        let n = resourceNames.count
        let name = resourceNames[((index % n) + n) % n]
        if let stereo = await makeStereoSphere(name: name) { return stereo }
        if let mono = await makeMonoSphere(name: name) { return mono }
        print("[Float] SpatialImageEnvironment: '\(name)' failed to load (stereo + mono)")
        return nil
    }

    /// Swap a prepared skybox in, removing the previous one so cycling doesn't stack spheres.
    @MainActor
    static func attach(_ sphere: ModelEntity, to container: Entity) {
        container.children
            .filter { $0.name == skyboxName }
            .forEach { $0.removeFromParent() }
        container.addChild(sphere)
    }

    // MARK: - Stereo

    /// Inward sphere with the `Stereo360` ShaderGraph material, its two eye textures set from
    /// the HEIC. Returns nil (→ mono fallback) if the material or either eye can't be loaded.
    @MainActor
    private static func makeStereoSphere(name: String) async -> ModelEntity? {
        do {
            var material = try await ShaderGraphMaterial(
                named: materialPrimPath, from: materialSceneName, in: realityKitContentBundle)
            // Texture creation also runs detached. TextureResource uploads ~300 MB per eye;
            // awaited from @MainActor the continuation resumes on main and any synchronous
            // portion blocks the frame. If RealityKit ever marks this init MainActor-bound
            // the compiler will reject this and the decode alone (above) is still off-main.
            let textures = try await Task.detached(priority: .userInitiated) {
                let eyes = try await loadEyes(name: name)
                let l = try await TextureResource(image: eyes.left,  options: .init(semantic: .color))
                let r = try await TextureResource(image: eyes.right, options: .init(semantic: .color))
                return StereoTextures(left: l, right: r)
            }.value
            let leftTex = textures.left, rightTex = textures.right
            try material.setParameter(name: leftParam,  value: .textureResource(leftTex))
            try material.setParameter(name: rightParam, value: .textureResource(rightTex))
            return makeSphere(material: material)
        } catch {
            // Expected while the material is still being authored — quiet, mono takes over.
            print("[Float] SpatialImageEnvironment: stereo material unavailable (\(error)) — mono fallback")
            return nil
        }
    }

    /// CGImage is immutable and thread-safe, but not formally Sendable; this box carries the
    /// pair back from the decode task without weakening anything else.
    private struct StereoTextures: @unchecked Sendable {
        let left: TextureResource
        let right: TextureResource
    }

    private struct EyePair: @unchecked Sendable {
        let left: CGImage
        let right: CGImage
    }

    /// Extract the left (CGImage 0) and right (CGImage 1) eyes from the bundled spatial HEIC,
    /// **off the main actor**.
    ///
    /// This used to be a synchronous call from `@MainActor` code, which was a real stall, not
    /// a micro-optimisation: `CGImageSourceCreateImageAtIndex` decodes without suspending, and
    /// these are two 12288x6144 frames — ~300 MB of pixels each. On the main actor that blocks
    /// every frame for the duration, which is what froze SplashView's animation (since removed —
    /// see SplashView, which is now static because the *remaining* stall is inside RealityKit's
    /// texture upload and cannot be moved). Nothing in here touches actor-isolated state, so it
    /// is safe on a detached task; the main actor now just awaits the result and stays live.
    private static func loadEyes(name: String) async throws -> EyePair {
        try await Task.detached(priority: .userInitiated) {
            // kCGImageSourceShouldCacheImmediately is the whole point of this options dict.
            // Without it CGImageSourceCreateImageAtIndex returns a LAZY CGImage: it hands
            // back a descriptor and defers the actual decode until something first touches
            // the pixels — which is inside TextureResource, back on the main actor. So the
            // first attempt at moving this work off-main moved only the file read, and the
            // 75-megapixel-per-eye decode still landed on the main thread and still froze
            // SplashView. Forcing the decode HERE is what actually relocates the cost.
            let opts: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
            guard let url = Bundle.main.url(forResource: name, withExtension: "heic"),
                  let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  CGImageSourceGetCount(src) >= 2,
                  let left  = CGImageSourceCreateImageAtIndex(src, 0, opts as CFDictionary),
                  let right = CGImageSourceCreateImageAtIndex(src, 1, opts as CFDictionary)
            else { throw SpatialError.eyesUnavailable }
            return EyePair(left: left, right: right)
        }.value
    }

    // MARK: - Mono fallback

    @MainActor
    private static func makeMonoSphere(name: String) async -> ModelEntity? {
        guard let tex = try? await TextureResource(named: name) else { return nil }
        var mat = UnlitMaterial()
        mat.color = .init(tint: .white, texture: .init(tex))
        return makeSphere(material: mat)
    }

    // MARK: - Shared

    @MainActor
    private static func makeSphere(material: any Material) -> ModelEntity {
        let sphere = ModelEntity(mesh: .generateSphere(radius: sphereRadius), materials: [material])
        sphere.name = skyboxName
        sphere.scale.z = -1   // flip winding so the inside surface renders (matches FarBackdrop)
        // Canonical facing: the equirect's centre column (u = 0.5) must be straight ahead
        // (-Z) at launch. Unrotated, it lands 90° to the user's LEFT (measured on device —
        // deep-sky composites centred at lon 0 needed a 90° CCW turn to face). -90° about Y
        // maps -X → -Z. Applies to every sky so the pipeline's "lon 0 = forward" holds.
        sphere.orientation = simd_quatf(angle: -.pi / 2, axis: [0, 1, 0])
        return sphere
    }
}
