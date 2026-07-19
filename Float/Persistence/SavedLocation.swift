import Foundation

/// §7e — a "Place". Tiny: seed + params + clock + thumbnail, not recorded positions.
struct SavedLocation: Codable, Identifiable {
    var id: UUID = UUID()
    var config: EnvironmentConfig     // seed + all generation params
    var simTime: Double               // restore moment for the deterministic layer
    var timeScale: Double
    var thumbnailFile: String         // the literal "screenshot" label in the gallery
    var createdAtEpoch: Double        // wall-clock label ONLY (never feeds generation)
    var generatorVersion: Int         // migration guard (§7e)
}

/// Loads/saves Places. The impact layer replays from initial conditions, not evolved
/// state (§7e) — a returned spot has the same setup with a fresh outcome.
@MainActor
final class SavedLocationStore {
    // TODO: persist [SavedLocation] via Codable JSON + thumbnail image files (or SwiftData).
    func save(_ loc: SavedLocation) { /* TODO */ }
    func load() -> [SavedLocation] { [] }
}
