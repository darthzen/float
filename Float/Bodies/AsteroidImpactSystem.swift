import RealityKit

/// §7d emergent layer: asteroid-on-asteroid collisions + pre-fracture fragmentation.
/// Free-running (NOT deterministic): saves restore initial conditions only (§7e).
struct AsteroidImpactSystem: System {
    init(scene: Scene) {}

    func update(context: SceneUpdateContext) {
        // TODO: promote rocks entering the "active zone" to dynamic rigid bodies
        //       (PhysicsBodyComponent + CollisionComponent). On an impact above an
        //       energy threshold, swap the intact rock for its precomputed Voronoi
        //       fragment set + a dust burst (§7d).
        //
        // SAFETY OVERRIDE (§9, hard rule): any fragment on a head-bound path FADES OUT
        // just before the safety bubble (deflection only as a fallback). The bubble
        // always wins — nothing reaches the user's face.
    }
}
