import SwiftUI
import RealityKit

/// App-wide observable state: immersion status + the currently active universe.
/// Spec: §7a (EnvironmentConfig drives everything), §5 (one clock), §7e (saved places).
@Observable
@MainActor
final class AppModel {
    static let immersiveSpaceID = "FloatSpace"

    enum ImmersionState { case closed, opening, open }
    var immersion: ImmersionState = .closed

    /// Which environment is currently shown. `importedSpatial` = the bundled Apple Spatial
    /// stereo image; `generated` = our procedural L1–L4 scene. Toggled for A/B comparison.
    enum EnvironmentSource { case importedSpatial, generated }
    var environmentSource: EnvironmentSource = .importedSpatial   // launch into the imported image

    /// Which bundled Apple Spatial sky is showing (index into SpatialImageEnvironment.resourceNames).
    var importedIndex: Int = 0

    /// The config that fully describes the current universe (§7a).
    var currentConfig: EnvironmentConfig = .random(seed: 0x0F10A7)

    /// Global animation clock (§5). Shared by every animated system.
    let clock = AnimationClock()

    /// Saved "Places" (§7e).
    var savedLocations: [SavedLocation] = []

    /// Persistent container holding the active universe root(s); environment swaps replace
    /// the root under it (§7b). Set by ImmersiveView once the scene builds.
    var sceneContainer: Entity?

    /// The §7b whiteout overlay entity; the jump flashes it to mask the swap. Set by ImmersiveView.
    var whiteout: Entity?

    /// The two toggleable environments, both mounted under the container so switching is just
    /// a visibility flip (no rebuild — see EnvironmentSource). Set by ImmersiveView.
    var generatedRoot: Entity?    // the SceneBuilder "UniverseRoot" (L1–L4)
    var importedRoot: Entity?     // the Apple Spatial image environment

    /// Show exactly one environment per `environmentSource`. Safe to call before `importedRoot`
    /// finishes its async load — it just no-ops on the nil side.
    func applyEnvironmentVisibility() {
        generatedRoot?.isEnabled = (environmentSource == .generated)
        importedRoot?.isEnabled  = (environmentSource == .importedSpatial)
    }

    /// Flip between the imported Apple Spatial image and the generated scene (A/B comparison).
    func toggleEnvironmentSource() {
        environmentSource = (environmentSource == .generated) ? .importedSpatial : .generated
        applyEnvironmentVisibility()
    }

    /// Advance to the next bundled Apple Spatial sky and swap it into the imported container.
    func advanceImportedImage() {
        guard let importedRoot else { return }
        importedIndex = (importedIndex + 1) % SpatialImageEnvironment.resourceNames.count
        Task { @MainActor in await SpatialImageEnvironment.load(index: importedIndex, into: importedRoot) }
    }

    /// Jump to a fresh environment (§7b): flash the whiteout, and swap under the peak of the
    /// flash so the change is masked. A stepping stone to the full streak sequence.
    func newEnvironment() {
        // "New Environment" acts on whatever you're looking at: cycle the imported skies, or
        // jump the generated universe.
        if environmentSource == .importedSpatial { advanceImportedImage(); return }
        guard let whiteout, sceneContainer != nil else { return }
        // Don't retrigger while a flash is already running.
        if whiteout.components[WhiteoutComponent.self]?.active == true { return }
        var c = whiteout.components[WhiteoutComponent.self] ?? WhiteoutComponent()
        c.active = true; c.elapsed = 0
        whiteout.components.set(c)

        // Swap at peak white (single-await Task — the reliable pattern). ~fadeIn + a bit.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.30))
            applyNewEnvironment()
        }
    }

    /// LIGHT in-place swap: full-scene rebuilds (~6k star entities) crashed the device render
    /// server, so keep the star field and only re-orient the backdrop + rebuild the
    /// (few-hundred-entity) nebula. Deterministic seed chain reproduces (§7e).
    private func applyNewEnvironment() {
        guard let container = sceneContainer,
              let root = container.children.first(where: { $0.name == "UniverseRoot" }) else { return }
        let nextSeed = currentConfig.seed &* 2862933555777941757 &+ 3037000493
        var newConfig = EnvironmentConfig.random(seed: nextSeed)

        // Cycle backdrops through a shuffle-bag so New Environment visits EVERY panorama
        // before any repeats — independent random draws (even unbiased) clustered on a few
        // skies. Overrides the seed-derived backdrop; density is re-derived for the pick so
        // the §7a busyness suppression still applies.
        var pick = SeededRandom(seed: nextSeed ^ 0x424B_4452_5348_4646)   // "BKDRSHFF"
        newConfig.backdrop = nextBackdrop(rng: &pick)
        newConfig.nebulaDensity = pick.unit() * FarBackdrop.nebulaScale(forBackdrop: newConfig.backdrop)

        currentConfig = newConfig
        let gen = EnvironmentGenerator(config: newConfig)

        // Backdrop: reskin in place — new panorama (config.backdrop) + orientation + tint.
        // Loads ONE 8K texture (light — not a full-scene rebuild), hidden by the whiteout.
        if let backdrop = root.findEntity(named: "L1_Backdrop") as? ModelEntity {
            FarBackdrop.reskin(backdrop, gen: gen)
        }

        // Nebula: rebuild just this layer (keep the heavy star field untouched).
        root.children.filter { $0.name.hasPrefix("L2_Nebula") }.forEach { $0.removeFromParent() }
        root.addChild(NebulaVolume.make(gen: gen))
    }

    /// Shuffle-bag over the backdrops: hand out each panorama once (in a seeded random
    /// order) before refilling, so New Environment cycles through ALL of them. Refill avoids
    /// opening on the sky we just showed, so there are no back-to-back repeats across bags.
    private var backdropBag: [Int] = []
    private func nextBackdrop(rng: inout SeededRandom) -> Int {
        let count = FarBackdrop.textureNames.count
        if backdropBag.isEmpty {
            var bag = Array(0..<count)
            for i in stride(from: count - 1, through: 1, by: -1) {      // Fisher–Yates
                let j = Int(rng.next() % UInt64(i + 1))
                bag.swapAt(i, j)
            }
            // removeLast() serves the pick, so keep bag.last (the next pick) off the current sky.
            if count > 1 && bag.last == currentConfig.backdrop { bag.swapAt(0, count - 1) }
            backdropBag = bag
        }
        return backdropBag.removeLast()
    }
}

/// Minimal launcher; the real experience is the immersive space.
struct LauncherView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    var body: some View {
        VStack(spacing: 16) {
            Text("Float").font(.extraLargeTitle)
            Text("Step into deep space.").foregroundStyle(.secondary)
            Button("Enter") {
                Task {
                    model.immersion = .opening
                    _ = await openImmersiveSpace(id: AppModel.immersiveSpaceID)
                    model.immersion = .open
                }
            }
            .buttonStyle(.borderedProminent)

            // TEMP trigger for the environment jump until the two-hand pinch-spread gesture
            // lands (see float-reveal-gesture). Only meaningful once you're in the space.
            Button("New Environment") { model.newEnvironment() }
                .buttonStyle(.bordered)
                .disabled(model.immersion != .open)

            // A/B toggle: imported Apple Spatial image  ⇄  generated scene.
            Button(model.environmentSource == .generated ? "Show Imported Image" : "Show Generated Scene") {
                model.toggleEnvironmentSource()
            }
            .buttonStyle(.bordered)
            .disabled(model.immersion != .open)
        }
        .padding(40)
    }
}
