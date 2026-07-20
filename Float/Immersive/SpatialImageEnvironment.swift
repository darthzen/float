import RealityKit
import RealityKitContent
import Foundation
import ImageIO
import CoreGraphics

/// Presents a bundled **Apple Spatial** (stereo 360° equirect) still as an immersive
/// environment, for A/B-ing real captured/authored skies against our procedurally generated
/// scene (§3/§4). Not part of the generated pipeline — it's a static sibling of UniverseRoot
/// that AppModel toggles on/off (EnvironmentSource) and cycles through (importedIndex).
///
/// Rendering: an **inward sphere** at ~infinity (wraps 360°, like FarBackdrop). Two material
/// paths, picked at load time:
///   • STEREO — a Reality Composer Pro `ShaderGraphMaterial` named `Stereo360` (a Camera Index
///     Switch selecting per-eye), with its `LeftEye`/`RightEye` texture parameters set at
///     runtime from the HEIC's two eyes (CGImage index 0 = left, 1 = right). See
///     Packages/RealityKitContent/README.md for how to author that material.
///   • MONO fallback — primary eye on an UnlitMaterial. Used until the `Stereo360` material
///     exists (or if it fails to load), so the build never breaks while it's being authored.
/// (visionOS 26 `ImagePresentationComponent` was tried first but renders a spatial photo as a
/// flat floating panel, not a surround, so it's wrong for an equirect environment.)
enum SpatialImageEnvironment {
    /// Bundled Apple Spatial HEICs (Resources/Textures/Backdrop, CREDITS.md). Cycled by AppModel.
    static let resourceNames = [
        "imported_spatial_1", "imported_spatial_2", "imported_spatial_3",
        "imported_spatial_4", "imported_spatial_5"
    ]

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
