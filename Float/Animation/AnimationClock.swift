import RealityKit

/// The single global clock (§5). Every animated value is a function of `simTime`.
/// `timeScale` is written by the control-panel slider (§7) and the hyperspace jump (§7b).
@MainActor
final class AnimationClock {
    private(set) var simTime: Double = 0
    var timeScale: Double = 1.0            // 0 = freeze … ~10x (open decision §11 #5)

    func advance(_ realDelta: Double) { simTime += realDelta * timeScale }

    /// Restore point for saved locations (§7e).
    func restore(simTime: Double, timeScale: Double) {
        self.simTime = simTime
        self.timeScale = timeScale
    }
}

/// ECS system that advances the clock each frame so layer systems can sample it.
struct AnimationClockSystem: System {
    init(scene: Scene) {}
    func update(context: SceneUpdateContext) {
        // TODO: advance the shared AnimationClock by context.deltaTime, then let layer
        //       systems read clock.simTime (§5). Provide the clock via a shared handle
        //       (e.g. a scene-level component) rather than a global.
    }
}
