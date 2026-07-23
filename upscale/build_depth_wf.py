#!/usr/bin/env python3
"""Build a ComfyUI API-format workflow: image -> Depth Anything V2 -> save.

Stage 1 of the spatial pipeline. Runs on the V100 in the ai/comfyui pod. Emits
a single-channel (well, RGB grayscale) depth map, near = bright, which
`stereo_synth.py` consumes.

kijai/ComfyUI-DepthAnythingV2 nodes (class names verified against /object_info):
  DownloadAndLoadDepthAnythingV2Model(model) -> DAMODEL
  DepthAnything_V2(da_model, images)         -> IMAGE (depth, near=bright)

Depth is low-frequency: DA V2 infers at ~518px internally, so feeding a ~2K-wide
source and upsampling the depth map on the Mac (stereo_synth resizes depth to the
full mono resolution) costs nothing in quality and keeps VRAM trivial — runs on
the 1070 as happily as the V100.

We POST this to /prompt. API format (not the UI graph format) = a flat dict of
{node_id: {class_type, inputs}}.  build_wf.py used the UI format for manual load;
this one is for programmatic submission.
"""
import json
import sys

MODEL = "depth_anything_v2_vitl_fp32.safetensors"   # vitl = best quality (§ grounded horizon)


def workflow(input_filename, out_prefix):
    return {
        "1": {
            "class_type": "LoadImage",
            "inputs": {"image": input_filename},
        },
        "2": {
            "class_type": "DownloadAndLoadDepthAnythingV2Model",
            "inputs": {"model": MODEL},
        },
        "3": {
            "class_type": "DepthAnything_V2",
            "inputs": {"da_model": ["2", 0], "images": ["1", 0]},
        },
        "4": {
            "class_type": "SaveImage",
            "inputs": {"filename_prefix": out_prefix, "images": ["3", 0]},
        },
    }


if __name__ == "__main__":
    inp = sys.argv[1] if len(sys.argv) > 1 else "your_source_image.png"
    pref = sys.argv[2] if len(sys.argv) > 2 else "depth"
    json.dump({"prompt": workflow(inp, pref)}, sys.stdout, indent=2)
