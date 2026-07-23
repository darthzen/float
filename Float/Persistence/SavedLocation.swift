import Foundation

/// §7e — a saved "Place". Since the app moved from a seed-generated universe to a fixed
/// library of pre-rendered stereo skies, a Place is no longer a seed + generation params —
/// it is simply *which sky* (by its bundle resource name) plus a display label and thumbnail.
/// The old deterministic-restore machinery (simTime / generatorVersion / seed) is gone with
/// the generated scene.
struct SavedLocation: Codable, Identifiable {
    var id: UUID = UUID()
    var sceneName: String        // SpatialImageEnvironment resource name
    var label: String            // user-facing name in the gallery
    var thumbnailFile: String    // the gallery thumbnail
    var createdAtEpoch: Double   // wall-clock label only
}

/// Loads/saves Places.
@MainActor
final class SavedLocationStore {
    // TODO: persist [SavedLocation] via Codable JSON + thumbnail image files (or SwiftData).
    func save(_ loc: SavedLocation) { /* TODO */ }
    func load() -> [SavedLocation] { [] }
}
