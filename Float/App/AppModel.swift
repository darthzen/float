import SwiftUI
import RealityKit

/// App-wide observable state. The generated L1–L4 universe was retired in favour of a fixed
/// library of pre-rendered stereo skies, so this is now just: which sky is showing, plus the
/// hooks the immersive scene needs to swap it. Spec: §7a (scene selection), §7e (saved Places).
@Observable
@MainActor
final class AppModel {
    static let immersiveSpaceID = "FloatSpace"

    enum ImmersionState { case closed, opening, open }
    var immersion: ImmersionState = .closed

    /// Index of the current sky in `SpatialImageEnvironment.catalog`.
    var currentScene: Int = 0

    /// Global animation clock (§5, foundational). Retained for future slow motion (e.g. a
    /// gentle backdrop yaw); nothing reads it while the scene is a static sphere.
    let clock = AnimationClock()

    /// Saved "Places" (§7e).
    var savedLocations: [SavedLocation] = []

    /// Set by ImmersiveView once the scene builds.
    var sceneContainer: Entity?   // persistent container
    var sceneRoot: Entity?        // the SpatialImageEnvironment sphere container
    var whiteout: Entity?         // §7b flash overlay

    // MARK: - Scene selection

    /// Show a specific sky by catalog index, masked by the §7b whiteout flash.
    func selectScene(_ index: Int) {
        let n = SpatialImageEnvironment.catalog.count
        guard n > 0 else { return }
        let idx = ((index % n) + n) % n
        currentScene = idx
        maskedSwap { [weak self] in self?.applyScene(idx) }
    }

    /// Jump to a random *different* sky. Uses a shuffle bag so every sky is visited once
    /// before any repeat (independent random draws clustered on a few). No determinism
    /// requirement here — this is a user action, not generation (§5 applied to the retired
    /// generated scene).
    func randomScene() {
        let n = SpatialImageEnvironment.catalog.count
        guard n > 1 else { if n == 1 { selectScene(0) }; return }
        if sceneBag.isEmpty {
            var bag = Array(0..<n).shuffled()
            if bag.last == currentScene { bag.swapAt(0, n - 1) }   // no immediate repeat
            sceneBag = bag
        }
        selectScene(sceneBag.removeLast())
    }

    private var sceneBag: [Int] = []

    /// Load the sky into the sphere. Falls through to the mono skybox if the stereo material
    /// or an eye can't load (SpatialImageEnvironment handles that).
    private func applyScene(_ index: Int) {
        guard let sceneRoot else { return }
        Task { @MainActor in await SpatialImageEnvironment.load(index: index, into: sceneRoot) }
    }

    /// Run `swap` under the peak of the §7b whiteout flash. Applies immediately if the overlay
    /// isn't mounted yet (e.g. a scene chosen from the launcher before entering the space).
    private func maskedSwap(_ swap: @escaping @MainActor () -> Void) {
        guard let whiteout else { swap(); return }
        if whiteout.components[WhiteoutComponent.self]?.active == true { return }
        var c = whiteout.components[WhiteoutComponent.self] ?? WhiteoutComponent()
        c.active = true; c.elapsed = 0
        whiteout.components.set(c)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.30))
            swap()
        }
    }
}

/// Launcher — the flat window that opens the immersive space and gives the three top-level
/// actions: a random sky, the scene picker, and the Entertainment sub-menu (Kindle / Music /
/// Video). Everything scene-related now targets the single spatial-image system.
struct LauncherView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.openWindow) private var openWindow

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
            .disabled(model.immersion != .closed)

            Button("Random Scene", systemImage: "shuffle") { model.randomScene() }
                .buttonStyle(.bordered)

            Button("Scenes…", systemImage: "square.grid.2x2") { openWindow(id: "scenes") }
                .buttonStyle(.bordered)

            Button("Entertainment", systemImage: "play.rectangle.on.rectangle") {
                openWindow(id: "entertainment")
            }
            .buttonStyle(.bordered)
        }
        .padding(40)
    }
}
