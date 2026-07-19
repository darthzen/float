import RealityKit

/// Deterministic builder: consumes a config, hands each subsystem its own seeded stream.
/// Spec: §5/§7e determinism — same config ⇒ same universe.
struct EnvironmentGenerator {
    let config: EnvironmentConfig
    private let rng: SeededRandom

    init(config: EnvironmentConfig) {
        self.config = config
        self.rng = SeededRandom(seed: config.seed)
    }

    // Named sub-streams keep each layer independent yet reproducible.
    func starStream()      -> SeededRandom { rng.stream(0x5741_5253) } // "STAR"
    func nebulaStream()    -> SeededRandom { rng.stream(0x4E45_4255) } // "NEBU"
    func asteroidStream()  -> SeededRandom { rng.stream(0x524F_434B) } // "ROCK"
    func phenomenaStream() -> SeededRandom { rng.stream(0x434F_4D54) } // "COMT"
    func backdropStream()  -> SeededRandom { rng.stream(0x424B_4452) } // "BKDR"
}
