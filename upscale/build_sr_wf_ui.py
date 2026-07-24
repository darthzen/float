#!/usr/bin/env python3
"""Emit the two production SR workflows in ComfyUI **UI format**, for study.

Rick's rule: every workflow driven via the API must also live in the web UI's
Workflows sidebar (/basedir/user/default/workflows/ on the pod). This emits:

  equirect_realesrgan_sr.json — plain RealESRGAN_x4plus model pass. Production
      recipe for equirect sources below the 12288 target (SPHEREx all-sky maps,
      any low-res pano). Won the 2026-07-24 A/B: faithful color on diffuse
      nebulosity, clean round stars, no tile seams, ~100x faster than diffusion.
      (Drivers wrap-pad 64px across the lon seam and crop after; the graph
      itself is just the model pass.)

  potm_usdu_master_sr.json — UltimateSDUpscale diffusion recipe (Realistic
      Vision V6.0 + 4x NMKD-Siax), device-approved for flat POTM/deep-sky
      masters (master_sr.py). upscale_by is per-run: min(4.0, stretch * 1.15).

Run:  python3 upscale/build_sr_wf_ui.py <outdir>
Then: kubectl cp <outdir>/*.json ai/<pod>:/basedir/user/default/workflows/
"""
import json
import os
import sys

USDU_POS = ("highly detailed, sharp focus, realistic photograph, natural texture, "
            "fine detail")
USDU_NEG = ("blurry, soft, noise, film grain, jpeg artifacts, compression, "
            "oversharpened, halo, plastic skin")


def build(nodes_spec, links_spec):
    nodes, links = [], []
    for i, (nid, typ, pos, size, inputs, outputs, widgets) in enumerate(nodes_spec):
        nodes.append({
            "id": nid, "type": typ, "pos": pos, "size": size, "flags": {},
            "order": i, "mode": 0,
            "inputs": [{"name": n, "type": t, "link": None} for n, t in inputs],
            "outputs": [{"name": n, "type": t, "links": [], "slot_index": s}
                        for s, (n, t) in enumerate(outputs)],
            "properties": {"Node name for S&R": typ}, "widgets_values": widgets,
        })
    by_id = {n["id"]: n for n in nodes}
    for lid, (s, ss, d, ds, t) in enumerate(links_spec, start=1):
        links.append([lid, s, ss, d, ds, t])
        by_id[s]["outputs"][ss]["links"].append(lid)
        by_id[d]["inputs"][ds]["link"] = lid
    return {"last_node_id": max(n["id"] for n in nodes), "last_link_id": len(links),
            "nodes": nodes, "links": links, "groups": [], "config": {}, "extra": {},
            "version": 0.4}


def realesrgan_wf():
    return build([
        (1, "LoadImage", [40, 220], [320, 320], [],
         [("IMAGE", "IMAGE"), ("MASK", "MASK")], ["equirect_source.png", "image"]),
        (2, "UpscaleModelLoader", [40, 60], [340, 80], [],
         [("UPSCALE_MODEL", "UPSCALE_MODEL")], ["RealESRGAN_x4plus.pth"]),
        (3, "ImageUpscaleWithModel", [440, 140], [280, 80],
         [("upscale_model", "UPSCALE_MODEL"), ("image", "IMAGE")],
         [("IMAGE", "IMAGE")], []),
        (4, "SaveImage", [780, 140], [380, 400],
         [("images", "IMAGE")], [], ["equirect_sr"]),
    ], [
        (2, 0, 3, 0, "UPSCALE_MODEL"),
        (1, 0, 3, 1, "IMAGE"),
        (3, 0, 4, 0, "IMAGE"),
    ])


def usdu_wf():
    # UltimateSDUpscale widgets follow input_order minus connections, with the UI's
    # control_after_generate widget right after seed (verified via /object_info).
    usdu_widgets = [4.0, 0, "fixed", 18, 6.0, "dpmpp_2m", "karras", 0.20, "Chess",
                    1024, 1024, 16, 32, "Band Pass", 1.0, 64, 8, 16, True, True, 1]
    return build([
        (1, "LoadImage", [40, 560], [320, 320], [],
         [("IMAGE", "IMAGE"), ("MASK", "MASK")], ["potm_master.png", "image"]),
        (2, "CheckpointLoaderSimple", [40, 40], [400, 100], [],
         [("MODEL", "MODEL"), ("CLIP", "CLIP"), ("VAE", "VAE")],
         ["realisticVisionV60B1_v51VAE.safetensors"]),
        (3, "CLIPTextEncode", [500, 40], [400, 140],
         [("clip", "CLIP")], [("CONDITIONING", "CONDITIONING")], [USDU_POS]),
        (4, "CLIPTextEncode", [500, 230], [400, 140],
         [("clip", "CLIP")], [("CONDITIONING", "CONDITIONING")], [USDU_NEG]),
        (5, "UpscaleModelLoader", [40, 420], [340, 80], [],
         [("UPSCALE_MODEL", "UPSCALE_MODEL")], ["4x_NMKD-Siax_200k.pth"]),
        (6, "UltimateSDUpscale", [960, 200], [340, 620],
         [("image", "IMAGE"), ("model", "MODEL"), ("positive", "CONDITIONING"),
          ("negative", "CONDITIONING"), ("vae", "VAE"),
          ("upscale_model", "UPSCALE_MODEL")],
         [("IMAGE", "IMAGE")], usdu_widgets),
        (7, "SaveImage", [1360, 200], [380, 400],
         [("images", "IMAGE")], [], ["potm_master_sr"]),
    ], [
        (1, 0, 6, 0, "IMAGE"),
        (2, 0, 6, 1, "MODEL"),
        (3, 0, 6, 2, "CONDITIONING"),
        (4, 0, 6, 3, "CONDITIONING"),
        (2, 2, 6, 4, "VAE"),
        (5, 0, 6, 5, "UPSCALE_MODEL"),
        (2, 1, 3, 0, "CLIP"),
        (2, 1, 4, 0, "CLIP"),
        (6, 0, 7, 0, "IMAGE"),
    ])


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
    for name, wf in [("equirect_realesrgan_sr", realesrgan_wf()),
                     ("potm_usdu_master_sr", usdu_wf())]:
        p = os.path.join(outdir, f"{name}.json")
        json.dump(wf, open(p, "w"), indent=2)
        d = json.load(open(p))
        ids = {n["id"] for n in d["nodes"]}
        ok = all(L[1] in ids and L[3] in ids for L in d["links"])
        print(f"{name}: nodes {len(d['nodes'])} links {len(d['links'])} links_ok {ok}")


if __name__ == "__main__":
    main()
