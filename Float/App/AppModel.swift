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

    /// Jump to a fresh environment (§7b): flash the whiteout, and swap under the peak of the
    /// flash so the change is masked. A stepping stone to the full streak sequence.
    func newEnvironment() {
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
        let newConfig = EnvironmentConfig.random(seed: nextSeed)
        currentConfig = newConfig
        let gen = EnvironmentGenerator(config: newConfig)

        // Backdrop: re-orient in place (cheap — no rebuild, no texture reload).
        if let backdrop = root.findEntity(named: "L1_Backdrop") {
            var rng = gen.backdropStream()
            let pi = Float.pi
            let u1 = rng.unit(), u2 = rng.unit(), u3 = rng.unit()
            backdrop.orientation = simd_quatf(vector: SIMD4<Float>(
                sqrt(1 - u1) * sin(2 * pi * u2), sqrt(1 - u1) * cos(2 * pi * u2),
                sqrt(u1) * sin(2 * pi * u3),     sqrt(u1) * cos(2 * pi * u3)))
        }

        // Nebula: rebuild just this layer (keep the heavy star field untouched).
        root.children.filter { $0.name.hasPrefix("L2_Nebula") }.forEach { $0.removeFromParent() }
        root.addChild(NebulaVolume.make(gen: gen))
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
        }
        .padding(40)
    }
}
