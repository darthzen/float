import RealityKit
import simd

/// §7d. Instanced drifting rocks — the premium depth element.
/// Ambient rocks NEVER enter the safety bubble (guaranteed at spawn time).
enum AsteroidField {
    static func make(_ cfg: AsteroidFieldConfig, gen: EnvironmentGenerator) -> Entity {
        let e = Entity(); e.name = "AsteroidField"
        var rng = gen.asteroidStream()

        for _ in 0..<cfg.count {
            // TODO: spawn on a lateral drift whose CLOSEST-APPROACH to the origin exceeds
            //       cfg.safetyRadius (§7d guaranteed-by-construction; no runtime avoidance).
            //       Axial tumble is fine; translational approach toward the head is not.
            _ = rng.next()
        }

        // §7f: a few slow "tame" rocks at arm's reach (~0.5–0.8 m) for flicking.
        for _ in 0..<cfg.tameRocksForFlicking {
            // TODO: reachable interactable rock — slow and consented, so it stays comfortable.
        }
        return e
    }
}
