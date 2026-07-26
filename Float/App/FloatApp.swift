import SwiftUI

/// App entry point. A small launcher window opens the full immersive space, which
/// IS the experience (no passthrough). Spec: §1, §7.
@main
struct FloatApp: App {
    @State private var model = AppModel()

    // Every panel here is `Window`, not `WindowGroup`: a WindowGroup is a *template* and
    // `openWindow(id:)` spawns a fresh instance each call, so re-tapping "Scenes…" — or the
    // §7 double-pinch, which fires whenever a pinch pair lands — stacked duplicate pickers
    // and menus in the space. `Window` is a singleton scene: opening an already-open one
    // just brings it forward.
    var body: some Scene {
        Window("Float", id: "launcher") {
            // LauncherView stays MOUNTED under the splash rather than being swapped for
            // it: its `.task` is what opens the immersive space, so gating it behind
            // `sceneReady` would mean nothing ever loads and the splash never lifts.
            ZStack {
                LauncherView()
                    .environment(model)
                if !model.sceneReady {
                    SplashView().transition(.opacity)
                }
            }
            // Explicit size because `.contentSize` shrink-wraps to the ideal size, and
            // SplashView has none (it is maxWidth/maxHeight .infinity by design). Without
            // this the launch window collapses around the menu and the splash renders in
            // a sliver.
            .frame(width: 720, height: 520)
            .animation(.easeInOut(duration: 0.8), value: model.sceneReady)
        }
        .windowResizability(.contentSize)

        // Web browser as its own window — the system gives it a drag bar + resize + eye-level
        // placement, so you can put it wherever you're lying. It reopens on whatever was last
        // open (Kindle Cloud Reader, in practice), so there is no "home page" to navigate to.
        Window("Browser", id: "browser") {
            BrowserView()
        }
        .defaultSize(width: 1100, height: 900)

        // Music (MusicKit, played in-process — see MusicPanel).
        Window("Music", id: "music") {
            MusicPanelView()
        }
        .defaultSize(width: 480, height: 640)

        // Local video from the photo library.
        Window("Video", id: "video") {
            VideoPanelView()
        }
        .defaultSize(width: 960, height: 620)

        // Scene picker (§7a) — its own window so it can be opened from inside the immersive
        // space and left floating while iterating on a specific sky.
        Window("Scenes", id: "scenes") {
            SceneSelectorView()
                .environment(model)
        }
        .defaultSize(width: 520, height: 640)

        // Entertainment sub-menu — Kindle / Music / Video.
        Window("Entertainment", id: "entertainment") {
            EntertainmentMenuView()
        }
        .defaultSize(width: 400, height: 480)

        ImmersiveSpace(id: AppModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(model)
        }
        // §1 — full immersion, everything else out of the way.
        .immersionStyle(selection: .constant(.full), in: .full)
    }
}
