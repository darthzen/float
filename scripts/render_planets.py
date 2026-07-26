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

# Sphere tessellation. 256x128 is well past what silhouette-smoothness needs at these angular
# sizes; the cost is trivial next to the textures and it keeps the limb from faceting when a
# body fills a large part of the view.
SEGMENTS, RINGS = 256, 128

# Axial tilt (degrees) applied about X so the poles do not sit dead vertical — a body lit and
# tilted reads as a world, a body square-on reads as a sticker. Venus is retrograde (177°),
# which is why its "north" ends up nearly upside down; that is correct, not a bug.
BODIES = {
    "iapetus": {"map": "iapetus_map_8192.png", "tilt": 15.5},
    "jupiter": {"map": "jupiter_map_8192.png", "tilt": 3.1},
    "saturn":  {"map": "saturn_map_8192.png",  "tilt": 26.7, "rings": True},
    "venus":   {"map": "Solarsystemscope_texture_8k_venus_surface.jpg", "tilt": 177.4},
}

# Saturn's rings, in globe radii. C ring inner edge to A ring outer edge.
RING_INNER, RING_OUTER = 1.235, 2.27
RING_ALPHA = "Solarsystemscope_texture_8k_saturn_ring_alpha.png"
RING_SEGMENTS = 512

# Sun placement. Off to one side and slightly above so there is a terminator to read depth
# from, but not so oblique that most of the body is unlit.
SUN_EULER = (0.0, 0.98, 0.60)   # radians
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


def add_sun():
    bpy.ops.object.light_add(type="SUN", location=(0, 0, 0))
    sun = bpy.context.object
    sun.rotation_euler = SUN_EULER
    sun.data.energy = 4.0
    # A real sun is not a point at this distance, and a hard-edged ring shadow looks CG.
    # ~0.53° is the sun's actual angular diameter from Earth; from Saturn it is far smaller,
    # but a little penumbra reads better than a razor edge.
    sun.data.angle = 0.009
    return sun


def make_globe(name, map_path, tilt_deg):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=SEGMENTS, ring_count=RINGS, radius=1.0)
    globe = bpy.context.object
    globe.name = name
    bpy.ops.object.shade_smooth()
    # The UV sphere primitive's default unwrap is already equirectangular (u wraps longitude,
    # v runs pole to pole), which is exactly how these maps are authored — no reprojection.
    globe.rotation_euler = (tilt_deg * 3.14159265 / 180.0, 0, 0)

    mat = bpy.data.materials.new(f"{name}_mat")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(str(map_path))
    # Colour maps are authored in sRGB; the default guess is right for jpg but be explicit so
    # the png-vs-jpg sources cannot end up graded differently from each other.
    tex.image.colorspace_settings.name = "sRGB"
    mat.node_tree.links.new(bsdf.inputs["Base Color"], tex.outputs["Color"])
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


def build(body, do_bake):
    spec = BODIES[body]
    map_path = SRC / spec["map"]
    if not map_path.exists():
        log(f"SKIP {body}: missing {map_path.name}")
        return
    log(f"=== {body} ({map_path.name}) ===")
    reset_scene()
    add_sun()
    globe, mat, tex = make_globe(body, map_path, spec["tilt"])
    objects = [globe]
    if spec.get("rings"):
        rings = make_rings(body)
        rings.rotation_euler = globe.rotation_euler   # rings sit in the equatorial plane
        objects.append(rings)

    export_usdz(objects, OUT / f"{body}.usdz")

    if do_bake and spec.get("rings"):
        log(f"{body}: baking ring/globe shadowing at {BAKE_SIZE} (slow)")
        bake_shadows(globe, mat, tex, body)
        export_usdz(objects, OUT / f"{body}_baked.usdz")


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

    # Swap the baked map in so the follow-up export carries it.
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    for link in list(mat.node_tree.links):
        if link.to_socket == bsdf.inputs["Base Color"]:
            mat.node_tree.links.remove(link)
    mat.node_tree.links.new(bsdf.inputs["Base Color"], target.outputs["Color"])


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", help="build a single body (%s)" % ", ".join(BODIES))
    ap.add_argument("--bake", action="store_true", help="also run the slow Saturn shadow bake")
    args = ap.parse_args(argv)

    OUT.mkdir(parents=True, exist_ok=True)
    todo = [args.only] if args.only else list(BODIES)
    for body in todo:
        if body not in BODIES:
            log(f"unknown body {body}")
            continue
        try:
            build(body, args.bake)
        except Exception as exc:                  # noqa: BLE001 - one body failing must not
            log(f"FAILED {body}: {exc}")          # take the rest of the batch down
            import traceback
            traceback.print_exc()
    log("done")


if __name__ == "__main__":
    main()
