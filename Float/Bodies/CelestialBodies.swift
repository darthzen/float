import RealityKit
import simd

/// §7c hero bodies at a fixed viewing distance (no surface LOD).
enum CelestialBodies {
    static func make(_ cfg: BodyConfig, gen: EnvironmentGenerator) -> Entity {
        switch cfg.kind {
        case .star: return makeStar(cfg, gen: gen)
        default:    return makePlanet(cfg, gen: gen)
        }
    }

    // Planet: single equirect texture + directional star light (terminator) + optional atmosphere + rings.
    static func makePlanet(_ cfg: BodyConfig, gen: EnvironmentGenerator) -> Entity {
        let e = Entity(); e.name = "Planet"
        e.position = [0, 0, -cfg.distance]
        // TODO: textured sphere; DirectionalLight from the local star for the day/night
        //       terminator (§7c); fresnel-rim atmosphere shell; optional cloud shell;
        //       slow spin driven off the clock.
        if cfg.hasRings { e.addChild(Rings.make(cfg, gen: gen)) }
        return e
    }

    // Star / Sun — emissive + corona + flares, LUMINANCE CAPPED (§7c, §9 eye-strain).
    static func makeStar(_ cfg: BodyConfig, gen: EnvironmentGenerator) -> Entity {
        let e = Entity(); e.name = "Star"
        e.position = [0, 0, -cfg.distance]
        // TODO: emissive sphere (granulation shader), corona sprites, occasional flares.
        //       CAP peak luminance + angular size; contain bloom (§9).
        return e
    }
}

/// §7c two-tier rings: textured bulk band + close-resolvable instanced debris.
enum Rings {
    static func make(_ cfg: BodyConfig, gen: EnvironmentGenerator) -> Entity {
        let e = Entity(); e.name = "Rings"
        // TODO: flat textured annulus (bulk band, Cassini gaps).
        // TODO: if cfg.ringsResolveClose — LOD-gated instanced rock belt on the near arc,
        //       reusing the AsteroidField instancing; in-plane orbit off the clock. Near
        //       debris honors the §7d safety bubble if the vantage is inside the ring plane.
        return e
    }
}
