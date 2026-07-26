import SwiftUI
import RealityKit
import ARKit
import QuartzCore
import simd

/// App-wide observable state. The generated L1–L4 universe was retired in favour of a fixed
/// library of pre-rendered stereo skies, so this is now just: which sky is showing, plus the
/// hooks the immersive scene needs to swap it. Spec: §7a (scene selection), §7e (saved Places).
@Observable
@MainActor
final class AppModel {
    static let immersiveSpaceID = "FloatSpace"

    enum ImmersionState { case closed, opening, open }
    var immersion: ImmersionState = .closed

    /// True once the FIRST sky has finished loading into the immersive space — the signal
    /// SplashView fades out on. Deliberately one-way: `immersion == .open` only means the
    /// space exists, and the real wait is decoding a ~100 MB stereo HEIC into two 12288×6144
    /// textures. Never reset on a scene change — swapping skies is masked by the §7b
    /// whiteout, and re-showing the launch view mid-session would read as a crash.
    var sceneReady = false

    /// Index of the current sky in `SpatialImageEnvironment.catalog`. Restored across
    /// launches by NAME (not index) so catalog additions/reorders don't shift the selection.
    var currentScene: Int = 0

    private static let lastSceneKey = "lastSceneName"

    init() {
        if let name = UserDefaults.standard.string(forKey: Self.lastSceneKey),
           let idx = SpatialImageEnvironment.catalog.firstIndex(where: { $0.name == name }) {
            currentScene = idx
        }
    }

    /// Global animation clock (§5, foundational). Retained for future slow motion (e.g. a
    /// gentle backdrop yaw); nothing reads it while the scene is a static sphere.
    let clock = AnimationClock()

    /// Saved "Places" (§7e).
    var savedLocations: [SavedLocation] = []

    /// Set by ImmersiveView once the scene builds.
    var sceneContainer: Entity?   // persistent container
    var sceneRoot: Entity?        // the SpatialImageEnvironment sphere container
    var whiteout: Entity?         // §7b flash overlay

    /// ARKit world tracking, handed over by ImmersiveView once its session is running.
    /// Its only consumer is `recenter()` — the device anchor is the head pose.
    var worldTracking: WorldTrackingProvider?

    /// First sky, decoded BEFORE the immersive space opens so the space is never empty.
    /// `ImmersiveView` consumes this once and clears it; nil afterwards, and nil if the
    /// preload failed (in which case the view falls back to loading in place).
    var preparedSky: ModelEntity?

    /// Decode the startup sky while the launcher/splash is still the only thing on screen.
    /// Ordering matters more than it looks: opening the space first and loading into it
    /// afterwards leaves the user staring into an empty black sphere for the length of a
    /// ~100 MB stereo HEIC decode. Doing it in this order costs the same wall time but
    /// spends it on a screen that has something to look at.
    func prepareFirstSky() async {
        guard preparedSky == nil else { return }
        preparedSky = await SpatialImageEnvironment.prepare(index: currentScene)
    }

    // MARK: - Recenter

    /// Yaw (radians, about +Y) currently applied to `sceneRoot` so the sky faces the user.
    /// Session-only — deliberately not persisted, and deliberately NOT reset by a scene
    /// change: it describes which way the user's body is pointing, not which sky is up.
    /// Living on the persistent `sceneRoot` container means a swap inherits it for free.
    private(set) var recenterYaw: Float = 0

    /// Make the direction the user is currently facing the scene's forward direction.
    ///
    /// **Yaw only.** Only the Y-axis component of the head pose is used; pitch and roll are
    /// discarded. The backdrop is a stereo 360 sphere whose per-eye disparity is baked
    /// horizontally in equirect space, so rotating content about any other axis tilts that
    /// baked disparity axis off the viewer's interocular axis and introduces vertical
    /// disparity — nauseating, not merely wrong-looking (§9, comfort is a gate).
    ///
    /// **Snaps, never animates.** Slewing the whole visual field is a textbook vection
    /// trigger; an instant cut is the comfortable option (§9). The camera does not move —
    /// only scene content rotates.
    /// Returns whether the recenter was actually applied. The launch auto-recenter polls on
    /// this: the device anchor is not tracked the instant the provider starts, so "did it
    /// take" has to be answerable rather than silently no-op.
    @discardableResult
    func recenter() -> Bool {
        guard let sceneRoot,
              let device = worldTracking?.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()),
              device.isTracked
        else { return false }

        // Head forward is the -Z column of the device transform. Keep only its horizontal
        // (x, z) part — that projection IS the yaw-only extraction.
        let m = device.originFromAnchorTransform
        let forward = SIMD2<Float>(-m.columns.2.x, -m.columns.2.z)
        // Degenerate when looking near-straight up or down: there is no meaningful facing
        // direction, so ignore the press rather than snap to an arbitrary heading.
        guard simd_length_squared(forward) > 1e-6 else { return false }

        // forward == (-sin θ, -cos θ) for a yaw of θ about +Y.
        recenterYaw = atan2(-forward.x, -forward.y)
        // Composes with (does not replace) the sphere's canonical -90° facing, which lives
        // on the child ModelEntity in SpatialImageEnvironment.makeSphere().
        sceneRoot.orientation = simd_quatf(angle: recenterYaw, axis: [0, 1, 0])
        return true
    }

    // MARK: - Scene selection

    /// Show a specific sky by catalog index, masked by the §7b whiteout flash.
    func selectScene(_ index: Int) {
        let n = SpatialImageEnvironment.catalog.count
        guard n > 0 else { return }
        // A swap is already under the mask: ignore this one rather than queue it. Checked
        // BEFORE `currentScene` is written, so the stored selection never claims a sky that
        // was never loaded. The in-flight window is the length of a decode, so this is a
        // real possibility on repeated taps, not a formality.
        if whiteout?.components[WhiteoutComponent.self]?.active == true { return }
        let idx = ((index % n) + n) % n
        currentScene = idx
        UserDefaults.standard.set(
            SpatialImageEnvironment.catalog[idx].name, forKey: Self.lastSceneKey)
        maskedSwap(to: idx)
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

    /// Swap the sky under the §7b flash, holding the flash at full black until the new sky is
    /// actually mounted. Falls through to the mono skybox if the stereo material or an eye
    /// can't load (SpatialImageEnvironment handles that).
    ///
    /// The decode starts at the same instant as the fade-in rather than after it, so the
    /// fade-in overlaps work that is already running off-main instead of being added in front
    /// of it. What the mask cannot do is *shorten* the decode: a swap now sits at black for
    /// however long the sky takes. That is the honest version of the old behaviour, which only
    /// looked quicker because it uncovered the previous sky and then jumped.
    private func maskedSwap(to index: Int) {
        guard let sceneRoot else { return }

        // No overlay mounted yet (e.g. a scene chosen from the launcher before entering the
        // space): there is nothing on screen to mask, so just load.
        guard let whiteout else {
            Task { @MainActor in
                await SpatialImageEnvironment.load(index: index, into: sceneRoot)
            }
            return
        }

        var c = whiteout.components[WhiteoutComponent.self] ?? WhiteoutComponent()
        guard !c.active else { return }
        c.active = true; c.elapsed = 0; c.holding = true
        whiteout.components.set(c)

        Task { @MainActor in
            let sphere = await SpatialImageEnvironment.prepare(index: index)

            // Don't uncover before the overlay is genuinely opaque. The flash advances on the
            // render clock, so this reads its real state rather than sleeping a matching
            // wall-clock interval and assuming the two agree. Terminates either way: `elapsed`
            // grows every frame, and the loop also exits if the overlay goes away with the
            // immersive space.
            while let cur = whiteout.components[WhiteoutComponent.self],
                  cur.active, cur.elapsed < cur.fadeIn {
                try? await Task.sleep(for: .milliseconds(8))
            }

            // A nil sphere means both stereo and mono failed; release anyway and fade back to
            // the sky that is already there rather than sit at black forever.
            if let sphere { SpatialImageEnvironment.attach(sphere, to: sceneRoot) }
            if var done = whiteout.components[WhiteoutComponent.self] {
                done.holding = false          // the fade-out starts on the next frame
                whiteout.components.set(done)
            }
        }
    }
}

/// Launcher — the flat window that opens the immersive space and gives the three top-level
/// actions: a random sky, the scene picker, and the Entertainment sub-menu (Kindle / Music /
/// Video). Everything scene-related now targets the single spatial-image system.
struct LauncherView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
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

            Button("Recenter", systemImage: "dot.viewfinder") { model.recenter() }
                .buttonStyle(.bordered)
                .disabled(model.immersion != .open)

            Button("Scenes…", systemImage: "square.grid.2x2") { openWindow(id: "scenes") }
                .buttonStyle(.bordered)

            Button("Entertainment", systemImage: "play.rectangle.on.rectangle") {
                openWindow(id: "entertainment")
            }
            .buttonStyle(.bordered)

            Button("Exit", systemImage: "power", role: .destructive) {
                // Leave cleanly: dismiss the immersive space first, then terminate. A hard
                // exit is fine for a single-user sideloaded app (no App Store review).
                Task {
                    if model.immersion == .open { await dismissImmersiveSpace() }
                    exit(0)
                }
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
        }
        .padding(40)
        .task {
            // Launch straight into the environment — the menu stays up for Scenes/Exit but
            // shouldn't gate entry. (The in-scene control panel's hand-tracking reveal is
            // still stubbed, so the launcher window must keep existing as the fallback UI.)
            guard model.immersion == .closed else { return }
            // `.opening` BEFORE the decode, not after: preparing now takes seconds, and
            // leaving the state at `.closed` for that long would keep the Enter button
            // live and let a tap start a second open underneath this one.
            model.immersion = .opening
            // Decode the sky FIRST, then open the space, so it comes up populated rather
            // than as black limbo the user waits inside. Same total wait, spent in front of
            // the splash instead. See AppModel.prepareFirstSky().
            await model.prepareFirstSky()
            _ = await openImmersiveSpace(id: AppModel.immersiveSpaceID)
            model.immersion = .open
        }
    }
}
