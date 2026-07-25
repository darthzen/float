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

  equirect_360_outpaint.json — sky360.py stage 1: the master feathered onto a
      2:1 canvas over a blurred extension of itself + mask, RV6.0 init-anchored
      inpaint (VAEEncode + SetLatentNoiseMask) at OUTPAINT_DENOISE.

  equirect_360_seam.json — sky360.py stage 2: the SAME graph on the roll-180
      canvas at SEAM_DENOISE, repainting the mirror-blended band so the sphere
      closes behind the viewer.

  equirect_360_usdu_refine.json — emitted ONLY when SKY360_REFINE=usdu. The USDU
      refine is off by default (it tiled dark sky into a visible grid), and this
      file is deliberately not written on the default path: the sidebar is for
      studying what actually ran, so a stage that is off must not appear in it.
      Delete any stale copy on the pod when switching back to the default.

Run:  python3 upscale/build_sr_wf_ui.py <outdir>
Then: kubectl cp <outdir>/*.json ai/<pod>:/basedir/user/default/workflows/
"""
import json
import os
import sys

from sky360 import (CKPT, NEG as SKY_NEG, OUTPAINT_CFG, OUTPAINT_DENOISE,
                    OUTPAINT_STEPS, POS_TMPL, REFINE_BACKEND, SEAM_DENOISE)

USDU_POS = ("highly detailed, sharp focus, realistic photograph, natural texture, "
            "fine detail")
USDU_NEG = ("blurry, soft, noise, film grain, jpeg artifacts, compression, "
            "oversharpened, halo, plastic skin")
SKY_POS = POS_TMPL.format(desc="a deep space nebula")


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


def usdu_wf(pos=USDU_POS, neg=USDU_NEG, upscale_by=4.0, denoise=0.20,
            input_name="potm_master.png", out_prefix="potm_master_sr"):
    # UltimateSDUpscale widgets follow input_order minus connections, with the UI's
    # control_after_generate widget right after seed (verified via /object_info).
    usdu_widgets = [upscale_by, 0, "fixed", 18, 6.0, "dpmpp_2m", "karras", denoise,
                    "Chess", 1024, 1024, 16, 32, "Band Pass", 1.0, 64, 8, 16, True,
                    True, 1]
    return build([
        (1, "LoadImage", [40, 560], [320, 320], [],
         [("IMAGE", "IMAGE"), ("MASK", "MASK")], [input_name, "image"]),
        (2, "CheckpointLoaderSimple", [40, 40], [400, 100], [],
         [("MODEL", "MODEL"), ("CLIP", "CLIP"), ("VAE", "VAE")],
         ["realisticVisionV60B1_v51VAE.safetensors"]),
        (3, "CLIPTextEncode", [500, 40], [400, 140],
         [("clip", "CLIP")], [("CONDITIONING", "CONDITIONING")], [pos]),
        (4, "CLIPTextEncode", [500, 230], [400, 140],
         [("clip", "CLIP")], [("CONDITIONING", "CONDITIONING")], [neg]),
        (5, "UpscaleModelLoader", [40, 420], [340, 80], [],
         [("UPSCALE_MODEL", "UPSCALE_MODEL")], ["4x_NMKD-Siax_200k.pth"]),
        (6, "UltimateSDUpscale", [960, 200], [340, 620],
         [("image", "IMAGE"), ("model", "MODEL"), ("positive", "CONDITIONING"),
          ("negative", "CONDITIONING"), ("vae", "VAE"),
          ("upscale_model", "UPSCALE_MODEL")],
         [("IMAGE", "IMAGE")], usdu_widgets),
        (7, "SaveImage", [1360, 200], [380, 400],
         [("images", "IMAGE")], [], [out_prefix]),
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


def outpaint_wf_ui(canvas="sky_canvas.png", mask="sky_mask.png",
                   out="sky_outpaint", denoise=OUTPAINT_DENOISE):
    return build([
        (1, "LoadImage", [40, 420], [320, 320], [],
         [("IMAGE", "IMAGE"), ("MASK", "MASK")], [canvas, "image"]),
        (2, "LoadImageMask", [40, 790], [320, 320], [],
         [("MASK", "MASK")], [mask, "red", "image"]),
        (3, "CheckpointLoaderSimple", [40, 40], [400, 100], [],
         [("MODEL", "MODEL"), ("CLIP", "CLIP"), ("VAE", "VAE")], [CKPT]),
        (4, "CLIPTextEncode", [500, 40], [400, 140],
         [("clip", "CLIP")], [("CONDITIONING", "CONDITIONING")], [SKY_POS]),
        (5, "CLIPTextEncode", [500, 230], [400, 140],
         [("clip", "CLIP")], [("CONDITIONING", "CONDITIONING")], [SKY_NEG]),
        (6, "VAEEncode", [500, 460], [240, 80],
         [("pixels", "IMAGE"), ("vae", "VAE")], [("LATENT", "LATENT")], []),
        (10, "SetLatentNoiseMask", [500, 600], [260, 90],
         [("samples", "LATENT"), ("mask", "MASK")], [("LATENT", "LATENT")], []),
        (7, "KSampler", [960, 200], [320, 470],
         [("model", "MODEL"), ("positive", "CONDITIONING"),
          ("negative", "CONDITIONING"), ("latent_image", "LATENT")],
         [("LATENT", "LATENT")],
         [0, "fixed", OUTPAINT_STEPS, OUTPAINT_CFG, "dpmpp_2m", "karras",
          denoise]),
        (8, "VAEDecode", [1320, 200], [240, 80],
         [("samples", "LATENT"), ("vae", "VAE")], [("IMAGE", "IMAGE")], []),
        (9, "SaveImage", [1600, 200], [380, 400],
         [("images", "IMAGE")], [], [out]),
    ], [
        (1, 0, 6, 0, "IMAGE"),
        (3, 2, 6, 1, "VAE"),
        (6, 0, 10, 0, "LATENT"),
        (2, 0, 10, 1, "MASK"),
        (3, 0, 7, 0, "MODEL"),
        (4, 0, 7, 1, "CONDITIONING"),
        (5, 0, 7, 2, "CONDITIONING"),
        (10, 0, 7, 3, "LATENT"),
        (3, 1, 4, 0, "CLIP"),
        (3, 1, 5, 0, "CLIP"),
        (7, 0, 8, 0, "LATENT"),
        (3, 2, 8, 1, "VAE"),
        (8, 0, 9, 0, "IMAGE"),
    ])


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
    emit = [("equirect_realesrgan_sr", realesrgan_wf()),
            ("potm_usdu_master_sr", usdu_wf()),
            ("equirect_360_outpaint", outpaint_wf_ui()),
            ("equirect_360_seam",
             outpaint_wf_ui("sky_rolled.png", "sky_band.png", "sky_seam", SEAM_DENOISE))]
    if REFINE_BACKEND == "usdu":
        emit.append(("equirect_360_usdu_refine",
                     usdu_wf(SKY_POS, SKY_NEG, REFINE_BY, REFINE_DENOISE,
                             "sky_outpaint.png", "sky_refined")))
    for name, wf in emit:
        p = os.path.join(outdir, f"{name}.json")
        json.dump(wf, open(p, "w"), indent=2)
        d = json.load(open(p))
        ids = {n["id"] for n in d["nodes"]}
        ok = all(L[1] in ids and L[3] in ids for L in d["links"])
        print(f"{name}: nodes {len(d['nodes'])} links {len(d['links'])} links_ok {ok}")


if __name__ == "__main__":
    main()
