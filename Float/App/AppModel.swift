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
        }
        .padding(40)
    }
}
