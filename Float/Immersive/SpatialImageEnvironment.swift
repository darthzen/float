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
        let n = resourceNames.count
        let name = resourceNames[((index % n) + n) % n]

        let sphere: ModelEntity
        if let stereo = await makeStereoSphere(name: name) {
            sphere = stereo
        } else if let mono = await makeMonoSphere(name: name) {
            sphere = mono
        } else {
            print("[Float] SpatialImageEnvironment: '\(name)' failed to load (stereo + mono)")
            return
        }

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
            let (left, right) = try loadEyes(name: name)
            let leftTex  = try await TextureResource(image: left,  options: .init(semantic: .color))
            let rightTex = try await TextureResource(image: right, options: .init(semantic: .color))
            try material.setParameter(name: leftParam,  value: .textureResource(leftTex))
            try material.setParameter(name: rightParam, value: .textureResource(rightTex))
            return makeSphere(material: material)
        } catch {
            // Expected while the material is still being authored — quiet, mono takes over.
            print("[Float] SpatialImageEnvironment: stereo material unavailable (\(error)) — mono fallback")
            return nil
        }
    }

    /// Extract the left (CGImage 0) and right (CGImage 1) eyes from the bundled spatial HEIC.
    private static func loadEyes(name: String) throws -> (CGImage, CGImage) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "heic"),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(src) >= 2,
              let left  = CGImageSourceCreateImageAtIndex(src, 0, nil),
              let right = CGImageSourceCreateImageAtIndex(src, 1, nil)
        else { throw SpatialError.eyesUnavailable }
        return (left, right)
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
        return sphere
    }
}
