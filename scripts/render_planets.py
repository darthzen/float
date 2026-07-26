#!/usr/bin/env python3
"""Build the four test planet/moon bodies as USDZ geometry for RealityKit.

Run under Blender, not bare python:

    /Applications/Blender.app/Contents/MacOS/Blender -b -P scripts/render_planets.py -- [--bake] [--only saturn]

WHY GEOMETRY AND NOT A PAINTED BACKDROP
    The sky HEICs sit at one near-infinite depth (depth_floor 0.94, ~0.2% baseline), so
    anything composited into the equirect has no parallax between the eyes. That is a large
    part of why the existing `saturn1` scene reads as a picture of space rather than a place.
    A body the viewer is supposed to feel near has to be real geometry with real stereo.

WHY CYCLES AND A BAKE (and only for Saturn)
    visionOS rejects RealityKit's `CustomMaterial` — only `ShaderGraphMaterial` authored in
    Reality Composer Pro, no hand-written Metal — so the app cannot render the two shadows
    that sell Saturn: the ring shadow banding the globe, and the globe's shadow thrown across
    the rings. Stage 2 currently bakes the FIRST of those only — the ring shadow onto the
    globe. The globe's shadow across the rings needs a bake target on the ring annulus, and
    the annulus UV here is deliberately 1-D (u = radius, v pinned) to match the strip texture,
    which leaves nothing to bake into. That needs a second UV set before it can work.
    What is baked is ray-traced here and painted into the colour map. Bake the LIGHTING,
    never the geometry: stereo parallax has to stay real, and a body that rotates once per
    ~10.6 h can afford frozen lighting. Jupiter, Venus and Iapetus have no self-shadowing
    feature to capture, so they ship unbaked and keep a live RealityKit light.

Stage 1 (always) exports plain textured USDZ for every body — fast, and enough to judge scale
and sharpness in the headset. Stage 2 (`--bake`) is the Saturn ring/globe shadow bake, which
is slow and the part most likely to need iterating; a stage-2 failure still leaves stage 1's
output on disk.
"""

import argparse
import os
import sys
from pathlib import Path

import bpy  # noqa: E402  (only importable inside Blender)

SRC = Path("/Volumes/Logic Pro/FloatScratch/planets")
OUT = Path("/Volumes/Logic Pro/FloatScratch/planets/usdz")
# Previews live in the repo (small) so triage.html can reference them like the sky
# thumbnails; the USDZ themselves stay on the scratch volume.
PREV = Path(__file__).resolve().parent.parent / "upscale" / "planet_prev"

# Sphere tessellation. 256x128 is well past what silhouette-smoothness needs at these angular
# sizes; the cost is trivial next to the textures and it keeps the limb from faceting when a
# body fills a large part of the view.
SEGMENTS, RINGS = 256, 128

# Axial tilt (degrees), applied about Y so the pole leans SIDEWAYS in view rather than
# toward the camera. For Saturn this is the difference between a wide-open bullseye of rings
# and the near-edge-on look of the saturn1 scene: with the tilt about X the ring plane was
# turned to face the viewer, so even a low camera saw them opened ~41 deg. About Y, the ring
# opening is set by camera elevation alone (see render_preview) and the tilt reads as a lean.
# Venus is retrograde (177 deg), which is why its "north" ends up nearly upside down; that is
# correct, not a bug.
#
# `grade` optionally boosts saturation/contrast. Real spacecraft colour for the gas giants is
# genuinely pale — the Voyager map below measures LESS saturated (0.111) than the artist
# texture it replaces (0.137) — so accuracy alone reads as washed out. The map is used for
# its structure, which is far better, and the grade puts the punch back.
BODIES = {
    # The colour mosaic, not the mono one: Iapetus's whole point is the two-tone split
    # between the bright trailing side and the dark Cassini Regio, which mono throws away.
    # 11741 px wide, so it also outresolves the 8192 mono.
    # sun_z: a shallow -20 deg instead of the default +40. The spin brought the dark
    # Cassini Regio round to face the camera, but the default sun then put that half in
    # night — a rotated body lit by an unmoved sun. This lights the side the spin exposes
    # and leaves only a soft terminator.
    "iapetus": {"map": "Iapetus_Color_Map.jpg", "tilt": 15.5, "spin": 0.75,
                "sun_z": -0.35},
    # Cassini (Dec 2000) global coverage merged with Juno polar imagery by Björn Jónsson,
    # 14400x7200 REAL — honest to ~62 deg, so this is the one body that can fill a lot of
    # view and stay sharp. Chosen over both the Solar System Scope artist texture (4096, no
    # resolved structure) and the Voyager 2 map (5760, but measurably the palest of the
    # three) because it actually carries the swirling cloud structure: festoons, white ovals,
    # the turbulent wake downstream of the Great Red Spot.
    # `spin` puts the GRS on the visible face — the biggest swirl on the planet.
    "jupiter": {"map": "jupiter_css_juno_14400.jpg", "tilt": 3.1, "spin": 0.58,
                "grade": {"sat": 1.35, "contrast": 0.15}},
    "saturn":  {"map": "saturn_map_8192.png",  "tilt": 26.7, "rings": True,
                "grade": {"sat": 1.25, "contrast": 0.05}},
    "venus":   {"map": "Solarsystemscope_texture_8k_venus_surface.jpg", "tilt": 177.4},
}

# Saturn's rings, in globe radii. C ring inner edge to A ring outer edge.
RING_INNER, RING_OUTER = 1.235, 2.27
RING_ALPHA = "Solarsystemscope_texture_8k_saturn_ring_alpha.png"
RING_SEGMENTS = 512

# Sun placement, as a rotation of the sun lamp's default -Z direction.
#
# 90 deg about X makes the light purely HORIZONTAL in world space (direction +Y, away from
# the camera → front-lit); -40 about Z then swings it 40 deg to the side, which is what puts
# a terminator on the globe instead of a flat full-face.
#
# The horizontal part is not an aesthetic choice, it is Saturn's geometry. The rings lie in
# the equatorial plane, which is the globe's 26.7 deg axial tilt — so the sun can NEVER be
# more than 26.7 deg above the ring plane. An earlier pass used 45 deg, which is physically
# impossible for Saturn and threw the entire ring shadow onto the night side, i.e. baked a
# map with no ring shadow in it at all. Keeping the light horizontal means the tilt alone
# sets the elevation (~20 deg here), which is both real and steep enough to land the shadow
# on the lit hemisphere where it can be seen.
#
# The SIGN of the Z term is not cosmetic — it decides which face of Saturn's rings is lit.
# The ring normal after the 26.7 deg tilt is (0.449, 0, 0.893) and the camera sits on its
# positive side. At Z = -40 the light direction is (0.643, 0.766, 0), so L·N = +0.289: the
# sun struck the BACK of the ring plane and the camera saw an unlit silhouette — the rings
# read as black bands. At Z = +40, L = (-0.643, 0.766, 0) and L·N = -0.289, lighting the face
# the camera actually sees. A single-sided flat annulus makes this an either/or.
SUN_EULER = (1.5708, 0.0, 0.698)    # radians (90 deg about X, +40 about Z)

# Per-body sun azimuth override (radians about Z), for bodies whose interesting feature is
# not where the default sun leaves it. One sun cannot serve every body: the azimuth that
# lights Saturn's rings also decides how much of Iapetus is in night.
SUN_Z_DEFAULT = 0.698
BAKE_SIZE = 8192   # match the source map; 4096 halved the angular resolution the "huge vs sharp" budget assumed


def log(msg):
    print(f"[planets] {msg}", flush=True)


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    # Metal GPU if this machine exposes one; Cycles falls back to CPU on its own if not.
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "METAL"
        prefs.get_devices()
        for dev in prefs.devices:
            dev.use = True
        scene.cycles.device = "GPU"
    except Exception as exc:                      # noqa: BLE001 - informational only
        log(f"GPU unavailable ({exc}); using CPU")
    scene.cycles.samples = 256


def add_sun(sun_z=None):
    bpy.ops.object.light_add(type="SUN", location=(0, 0, 0))
    sun = bpy.context.object
    sun.rotation_euler = (SUN_EULER[0], SUN_EULER[1],
                          SUN_Z_DEFAULT if sun_z is None else sun_z)
    sun.data.energy = 4.0
    # A real sun is not a point at this distance, and a hard-edged ring shadow looks CG.
    # ~0.53° is the sun's actual angular diameter from Earth; from Saturn it is far smaller,
    # but a little penumbra reads better than a razor edge.
    sun.data.angle = 0.009
    return sun


def make_globe(name, map_path, tilt_deg, grade=None, spin=0.0):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=SEGMENTS, ring_count=RINGS, radius=1.0)
    globe = bpy.context.object
    globe.name = name
    bpy.ops.object.shade_smooth()
    # The UV sphere primitive's default unwrap is already equirectangular (u wraps longitude,
    # v runs pole to pole), which is exactly how these maps are authored — no reprojection.
    # Tilt about Y — see the note on BODIES for why not X.
    globe.rotation_euler = (0, tilt_deg * 3.14159265 / 180.0, 0)

    # `spin` turns the body about its own polar axis by shifting the equirect u coordinate,
    # choosing which longitude faces the camera. It decides whether Iapetus shows its famous
    # two-tone boundary or just a grey hemisphere.
    #
    # Done by editing the mesh UVs, NOT with a Mapping node. A Mapping node works in Cycles
    # but Blender does not write it into the USD — checked, and the exported .usdc had no
    # UsdTransform2d — so the preview would have shown a spun body while the actual asset
    # shipped unspun. UVs are mesh data and always export.
    #
    # No modulo: values outside [0,1] are fine with REPEAT extension, whereas wrapping them
    # would leave the faces spanning the seam with u running 0.99 -> 0.01 and smear the whole
    # texture across that column.
    if spin:
        tex_layer = globe.data.uv_layers.active.data
        for loop in tex_layer:
            loop.uv[0] += spin

    mat = bpy.data.materials.new(f"{name}_mat")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(str(map_path))
    # Colour maps are authored in sRGB; the default guess is right for jpg but be explicit so
    # the png-vs-jpg sources cannot end up graded differently from each other.
    tex.image.colorspace_settings.name = "sRGB"

    # Optional grade between the map and the shader. Done in nodes rather than by editing the
    # source file so the map on disk stays the untouched original — the grade is a look, and
    # looks get revised.
    src = tex.outputs["Color"]
    if grade:
        hs = mat.node_tree.nodes.new("ShaderNodeHueSaturation")
        hs.inputs["Saturation"].default_value = grade.get("sat", 1.0)
        mat.node_tree.links.new(hs.inputs["Color"], src)
        src = hs.outputs["Color"]
        if grade.get("contrast"):
            bc = mat.node_tree.nodes.new("ShaderNodeBrightContrast")
            bc.inputs["Contrast"].default_value = grade["contrast"]
            mat.node_tree.links.new(bc.inputs["Color"], src)
            src = bc.outputs["Color"]

    mat.node_tree.links.new(bsdf.inputs["Base Color"], src)
    bsdf.inputs["Roughness"].default_value = 0.9   # no specular hotspot on a rock or a cloud deck
    bsdf.inputs["Metallic"].default_value = 0.0
    globe.data.materials.append(mat)
    return globe, mat, tex


def make_rings(name):
    """Flat annulus with radial UVs.

    The SSS ring texture is a strip (8192x~500) where the X axis IS radial position, so the
    unwrap has to map u = normalised radius rather than anything the automatic unwrappers
    would produce. Building the mesh by hand is the short path to that.
    """
    import bmesh

    mesh = bpy.data.meshes.new(f"{name}_rings")
    obj = bpy.data.objects.new(f"{name}_rings", mesh)
    bpy.context.collection.objects.link(obj)

    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new()
    import math
    inner, outer = [], []
    for i in range(RING_SEGMENTS):
        a = 2 * math.pi * i / RING_SEGMENTS
        inner.append(bm.verts.new((math.cos(a) * RING_INNER, math.sin(a) * RING_INNER, 0)))
        outer.append(bm.verts.new((math.cos(a) * RING_OUTER, math.sin(a) * RING_OUTER, 0)))
    bm.verts.ensure_lookup_table()
    for i in range(RING_SEGMENTS):
        j = (i + 1) % RING_SEGMENTS
        face = bm.faces.new((inner[i], outer[i], outer[j], inner[j]))
        # u: 0 at the inner edge, 1 at the outer edge. v is unused by a 1-D strip.
        for loop, u in zip(face.loops, (0.0, 1.0, 1.0, 0.0)):
            loop[uv_layer].uv = (u, 0.5)
    bm.to_mesh(mesh)
    bm.free()

    mat = bpy.data.materials.new(f"{name}_rings_mat")
    mat.use_nodes = True
    mat.blend_method = "BLEND"
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(str(SRC / RING_ALPHA))
    tex.extension = "EXTEND"   # never wrap: sampling past the outer edge must not fetch the C ring
    mat.node_tree.links.new(bsdf.inputs["Base Color"], tex.outputs["Color"])
    mat.node_tree.links.new(bsdf.inputs["Alpha"], tex.outputs["Alpha"])
    bsdf.inputs["Roughness"].default_value = 1.0
    obj.data.materials.append(mat)
    return obj


def export_usdz(objects, path):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.usd_export(
        filepath=str(path),
        selected_objects_only=True,
        export_textures_mode="NEW",     # copy the maps into the package
        # Explicit, because the default is a downscale target and these maps are the whole
        # point: an 8192 map quietly resampled to 4096 halves the angular resolution the
        # "huge vs sharp" budget was worked out against.
        usdz_downscale_size="KEEP",
        relative_paths=False,
        generate_preview_surface=True,  # UsdPreviewSurface — what RealityKit actually reads
        # Blender is Z-up, USD/RealityKit is Y-up. Converting here means the asset arrives
        # upright instead of needing a corrective rotation at every load site.
        convert_orientation=True,
        export_global_up_selection="Y",
        export_global_forward_selection="NEGATIVE_Z",
    )
    log(f"wrote {path.name} ({path.stat().st_size / 1e6:.1f} MB)")


def build(body, do_bake, do_preview=False):
    spec = BODIES[body]
    map_path = SRC / spec["map"]
    if not map_path.exists():
        log(f"SKIP {body}: missing {map_path.name}")
        return
    log(f"=== {body} ({map_path.name}) ===")
    reset_scene()
    add_sun(spec.get("sun_z"))
    globe, mat, tex = make_globe(body, map_path, spec["tilt"], spec.get("grade"), spec.get("spin", 0.0))
    objects = [globe]
    if spec.get("rings"):
        rings = make_rings(body)
        rings.rotation_euler = globe.rotation_euler   # rings sit in the equatorial plane
        objects.append(rings)

    r_eff = RING_OUTER if spec.get("rings") else 1.0
    export_usdz(objects, OUT / f"{body}.usdz")
    if do_preview:
        render_preview(objects, body, r_eff)

    if do_bake and spec.get("rings"):
        log(f"{body}: baking ring/globe shadowing at {BAKE_SIZE} (slow)")
        bake_shadows(globe, mat, tex, body)
        export_usdz(objects, OUT / f"{body}_baked.usdz")
        if do_preview:
            render_preview(objects, f"{body}_baked", r_eff)


def bake_shadows(globe, mat, tex, name):
    """Bake COMBINED lighting into a new map so the ring shadow survives export.

    This is the only reason Blender is in this pipeline at all. RealityKit on visionOS cannot
    be made to cast the ring shadow onto the globe, so it gets painted in.
    """
    img = bpy.data.images.new(f"{name}_baked", BAKE_SIZE, BAKE_SIZE // 2)
    target = mat.node_tree.nodes.new("ShaderNodeTexImage")
    target.image = img
    # Cycles bakes into whichever image node is ACTIVE — not the one that is linked. The
    # source texture stays wired to Base Color so its colour is part of what gets baked.
    mat.node_tree.nodes.active = target

    scene = bpy.context.scene
    scene.cycles.bake_type = "COMBINED"
    scene.render.bake.use_pass_direct = True
    scene.render.bake.use_pass_indirect = True
    scene.render.bake.margin = 16

    bpy.ops.object.select_all(action="DESELECT")
    globe.select_set(True)
    bpy.context.view_layer.objects.active = globe
    bpy.ops.object.bake(type="COMBINED")

    out = OUT / f"{name}_baked.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    img.filepath_raw = str(out)
    img.file_format = "PNG"
    img.save()
    log(f"baked -> {out.name}")

    # Swap the baked map in as EMISSION, not base colour, and black out the diffuse.
    #
    # A baked map already contains the lighting. Feeding it back into Base Color leaves it
    # lit a second time — by Cycles here, and by whatever light RealityKit has in the scene
    # there — which is what washed the first attempt's terminator and ring shadow back out.
    # Routing it to emission makes the surface unlit: what you baked is exactly what shows.
    # UsdPreviewSurface carries this as `emissiveColor`, which is what RealityKit reads.
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    for link in list(mat.node_tree.links):
        if link.to_socket in (bsdf.inputs["Base Color"], bsdf.inputs["Emission Color"]):
            mat.node_tree.links.remove(link)
    bsdf.inputs["Base Color"].default_value = (0, 0, 0, 1)
    mat.node_tree.links.new(bsdf.inputs["Emission Color"], target.outputs["Color"])
    bsdf.inputs["Emission Strength"].default_value = 1.0


def render_preview(objects, name, r_eff):
    """Camera render of the body for the triage page.

    2:1 to match the card aspect on triage.html — the grid crops anything else and would
    slice the rings off Saturn. Distance is derived from the body's effective radius rather
    than hand-set per body, so Iapetus and ringed Saturn frame the same way.
    """
    scene = bpy.context.scene
    scene.render.resolution_x, scene.render.resolution_y = 1600, 800
    scene.render.film_transparent = False
    scene.cycles.samples = 128

    world = bpy.data.worlds.new("preview_world")
    scene.world = world
    world.use_nodes = True
    # Not pure black: a hair of ambient keeps the unlit limb from clipping into the
    # background, which is what makes a render read as a cutout.
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.004, 0.005, 0.011, 1)

    # 5x the effective radius puts the body at ~55% of frame width.
    #
    # Elevation is the ring-opening control now that the axial tilt leans sideways rather
    # than toward the camera: opening = asin(cos(tilt) * z / hypot(d, z)). At z = 1.2 that is
    # ~12 deg, i.e. the near-edge-on read of the saturn1 scene, rather than the ~41 deg
    # bullseye the tilt-toward-camera setup produced regardless of where the camera sat.
    bpy.ops.object.camera_add(location=(0, -5.0 * r_eff, 1.2 * r_eff))
    cam = bpy.context.object
    scene.camera = cam
    track = cam.constraints.new(type="TRACK_TO")
    track.target = objects[0]          # always aim at the globe, rings or not
    track.track_axis = "TRACK_NEGATIVE_Z"
    track.up_axis = "UP_Y"

    # JPEG, matching the sky thumbnails: these are triage previews committed to the repo, and
    # lossless PNG costs ~1.6 MB apiece for something only ever looked at in a browser grid.
    out = PREV / f"{name}.jpg"
    out.parent.mkdir(parents=True, exist_ok=True)
    scene.render.filepath = str(out)
    scene.render.image_settings.file_format = "JPEG"
    scene.render.image_settings.quality = 92
    bpy.ops.render.render(write_still=True)
    log(f"preview -> {out.name}")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", help="build a single body (%s)" % ", ".join(BODIES))
    ap.add_argument("--bake", action="store_true", help="also run the slow Saturn shadow bake")
    ap.add_argument("--preview", action="store_true", help="also render triage preview images")
    args = ap.parse_args(argv)

    OUT.mkdir(parents=True, exist_ok=True)
    todo = [args.only] if args.only else list(BODIES)
    for body in todo:
        if body not in BODIES:
            log(f"unknown body {body}")
            continue
        try:
            build(body, args.bake, args.preview)
        except Exception as exc:                  # noqa: BLE001 - one body failing must not
            log(f"FAILED {body}: {exc}")          # take the rest of the batch down
            import traceback
            traceback.print_exc()
    log("done")


if __name__ == "__main__":
    main()
