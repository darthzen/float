import RealityKit

/// The single global clock (§5). Every animated value is a function of `simTime`.
/// `timeScale` scales it. 0 = freeze, ~10x max (open decision §11 #5).
@MainActor
final class AnimationClock {
    private(set) var simTime: Double = 0
    var timeScale: Double = 1.0

    func advance(_ realDelta: Double) { simTime += realDelta * timeScale }

    /// Restore point for saved locations (§7e).
    func restore(simTime: Double, timeScale: Double) {
        self.simTime = simTime
        self.timeScale = timeScale
    }
}

/// Scene-level handle so ECS systems can reach the clock without a global (§5).
struct ClockComponent: Component {
    var clock: AnimationClock
}

/// ECS system that advances the clock each frame.
/// RealityKit systems on visionOS run on the main thread, so assumeIsolated is safe.
struct AnimationClockSystem: System {
    static let query = EntityQuery(where: .has(ClockComponent.self))

    init(scene: Scene) {}

    func update(context: SceneUpdateContext) {
        MainActor.assumeIsolated {
            for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
                if let comp = entity.components[ClockComponent.self] {
                    comp.clock.advance(context.deltaTime)
                    return
                }
            }
        }
    }
}
