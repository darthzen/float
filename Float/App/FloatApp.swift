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

        ImmersiveSpace(id: AppModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(model)
        }
        // §1 — full immersion, everything else out of the way.
        .immersionStyle(selection: .constant(.full), in: .full)
    }
}
