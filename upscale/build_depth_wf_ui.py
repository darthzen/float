#!/usr/bin/env python3
"""Emit the depth workflow in ComfyUI **UI format** (editable canvas), for study.

build_depth_wf.py emits API format (flat dict) for POST /prompt — that runs but
is NOT loadable as a graph in the browser. This emits the same graph in the UI
format the ComfyUI web canvas reads (nodes with positions + links), matching the
build_wf.py convention. Drop the output in /basedir/user/default/workflows/ and
it appears in the browser's Workflows sidebar.

Graph:  LoadImage --image--> DepthAnything_V2 <--da_model-- DownloadAndLoadModel
        DepthAnything_V2 --image--> SaveImage
"""
import json
import sys

links = []
_lid = [0]


def link(src, sslot, dst, dslot, typ):
    _lid[0] += 1
    links.append([_lid[0], src, sslot, dst, dslot, typ])
    return _lid[0]


nodes = []


def node(nid, typ, pos, size, inputs, outputs, widgets):
    nodes.append({
        "id": nid, "type": typ, "pos": pos, "size": size, "flags": {},
        "order": nid - 1, "mode": 0, "inputs": inputs, "outputs": outputs,
        "properties": {"Node name for S&R": typ}, "widgets_values": widgets,
    })


node(1, "LoadImage", [40, 320], [320, 320], [],
     [{"name": "IMAGE", "type": "IMAGE", "links": [], "slot_index": 0},
      {"name": "MASK", "type": "MASK", "links": [], "slot_index": 1}],
     ["ground_rogland_night.png", "image"])

# Loader: model dropdown + precision. vitl_fp32 = best quality (grounded horizon).
node(2, "DownloadAndLoadDepthAnythingV2Model", [40, 40], [400, 100], [],
     [{"name": "da_model", "type": "DAMODEL", "links": [], "slot_index": 0}],
     ["depth_anything_v2_vitl_fp32.safetensors", "fp32"])

node(3, "DepthAnything_V2", [480, 160], [320, 100],
     [{"name": "da_model", "type": "DAMODEL", "link": None},
      {"name": "images", "type": "IMAGE", "link": None}],
     [{"name": "IMAGE", "type": "IMAGE", "links": [], "slot_index": 0}],
     [])

node(4, "SaveImage", [840, 160], [380, 400],
     [{"name": "images", "type": "IMAGE", "link": None}], [],
     ["depth"])


def set_out(nid, slot, lid):
    for n in nodes:
        if n["id"] == nid:
            n["outputs"][slot]["links"].append(lid)


def set_in(nid, slot, lid):
    for n in nodes:
        if n["id"] == nid:
            n["inputs"][slot]["link"] = lid


for (s, ss, d, ds, t) in [(2, 0, 3, 0, "DAMODEL"),
                          (1, 0, 3, 1, "IMAGE"),
                          (3, 0, 4, 0, "IMAGE")]:
    lid = link(s, ss, d, ds, t)
    set_out(s, ss, lid)
    set_in(d, ds, lid)

wf = {"last_node_id": 4, "last_link_id": _lid[0], "nodes": nodes, "links": links,
      "groups": [], "config": {}, "extra": {}, "version": 0.4}

out = sys.argv[1] if len(sys.argv) > 1 else "/dev/stdout"
json.dump(wf, open(out, "w"), indent=2)
if out != "/dev/stdout":
    d = json.load(open(out))
    ids = {n["id"] for n in d["nodes"]}
    ok = all(L[1] in ids and L[3] in ids for L in d["links"])
    print(f"nodes: {len(d['nodes'])} links: {len(d['links'])} links_ok: {ok}")
