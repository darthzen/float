import SwiftUI

/// App entry point. A small launcher window opens the full immersive space, which
/// IS the experience (no passthrough). Spec: §1, §7.
@main
struct FloatApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup(id: "launcher") {
            LauncherView()
                .environment(model)
        }
        .windowResizability(.contentSize)

        // Reading panel (Kindle Cloud Reader etc.) as its own window — the system gives it a
        // drag bar + resize + eye-level placement, so you can put it wherever you're lying.
        WindowGroup(id: "reader") {
            ReaderPanelView()
        }
        .defaultSize(width: 640, height: 900)

        // Scene picker (§7a) — its own window so it can be opened from inside the immersive
        // space and left floating while iterating on a specific sky.
        WindowGroup(id: "scenes") {
            SceneSelectorView()
                .environment(model)
        }
        .defaultSize(width: 520, height: 640)

        // Entertainment sub-menu — Kindle / Music / Video.
        WindowGroup(id: "entertainment") {
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
