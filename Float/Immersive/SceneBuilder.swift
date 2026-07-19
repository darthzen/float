import RealityKit

/// Assembles the layered depth scene (§3) from an EnvironmentConfig (§7a).
/// Every layer is a child of one stationary root at the origin (§9: camera never moves).
enum SceneBuilder {
    static func build(config: EnvironmentConfig, clock: AnimationClock) -> Entity {
        let root = Entity()
        root.name = "UniverseRoot"

        let gen = EnvironmentGenerator(config: config)

        root.addChild(FarBackdrop.make(gen: gen))       // L1 §4
        root.addChild(NebulaVolume.make(gen: gen))      // L2 nebula (splat / particle fallback)
        root.addChild(StarVolume.make(gen: gen))        // L3 — the depth workhorse
        root.addChild(PhenomenaSpawner.make(gen: gen))  // L4 §6

        if let body = config.body {
            root.addChild(CelestialBodies.make(body, gen: gen))          // §7c
        }
        if let field = config.asteroidField {
            root.addChild(AsteroidField.make(field, gen: gen))           // §7d
        }
        return root
    }
}
