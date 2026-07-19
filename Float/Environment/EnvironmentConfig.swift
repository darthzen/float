import simd

/// Full description of a "universe" — the only thing a saved location stores (§7a, §7e).
struct EnvironmentConfig: Codable, Equatable {
    var seed: UInt64
    var generatorVersion: Int = 1          // §7e migration guard

    // Nebula (L2)
    enum NebulaBackend: String, Codable { case splat, particles }
    var nebulaBackend: NebulaBackend = .splat
    var nebulaPalette: Int = 0
    var nebulaDensity: Float = 0.6

    // Stars (L3)
    var starDensity: Float = 1.0
    var starColorMix: Float = 0.5

    // Backdrop (L1)
    var backdrop: Int = 0

    // Phenomena rates (L4, §6)
    var cometRate: Float = 0.1
    var meteorRate: Float = 0.4

    // Optional hero content
    var body: BodyConfig? = nil                    // §7c
    var asteroidField: AsteroidFieldConfig? = nil  // §7d

    static func random(seed: UInt64) -> EnvironmentConfig {
        var rng = SeededRandom(seed: seed)
        var c = EnvironmentConfig(seed: seed)
        c.nebulaPalette = Int(rng.next() % 8)
        c.nebulaDensity = rng.unit()
        // TODO: roll body / asteroidField per §7a variety policy (open decision §11 #7).
        return c
    }
}

/// §7c hero body.
struct BodyConfig: Codable, Equatable {
    enum Kind: String, Codable { case proceduralPlanet, namedBody, star }
    var kind: Kind = .proceduralPlanet
    var named: String? = nil                 // e.g. "Saturn" for the Sol System preset
    var hasRings: Bool = false
    var ringsResolveClose: Bool = true       // §7c two-tier rings
    var atmosphereTint: SIMD3<Float> = [0.4, 0.6, 1.0]
    var distance: Float = 90                 // §3 hero distance ~40–150 m
}

/// §7d asteroid field.
struct AsteroidFieldConfig: Codable, Equatable {
    var count: Int = 300
    var safetyRadius: Float = 2.5            // §7d/§9 exclusion bubble — never violated
    var enableImpacts: Bool = true          // §7d emergent layer (free-running)
    var tameRocksForFlicking: Int = 3       // §7f reachable rocks (open decision §11 #14)
}
