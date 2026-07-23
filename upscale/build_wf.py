import json

links=[]; _lid=[0]
def link(src,sslot,dst,dslot,typ):
    _lid[0]+=1; links.append([_lid[0],src,sslot,dst,dslot,typ]); return _lid[0]
nodes=[]
def node(nid,typ,pos,size,inputs,outputs,widgets):
    nodes.append({"id":nid,"type":typ,"pos":pos,"size":size,"flags":{},"order":nid-1,
        "mode":0,"inputs":inputs,"outputs":outputs,
        "properties":{"Node name for S&R":typ},"widgets_values":widgets})

node(1,"LoadImage",[40,320],[320,320],[],
     [{"name":"IMAGE","type":"IMAGE","links":[],"slot_index":0},
      {"name":"MASK","type":"MASK","links":[],"slot_index":1}],
     ["your_source_image.png","image"])

node(2,"CheckpointLoaderSimple",[40,10],[320,110],[],
     [{"name":"MODEL","type":"MODEL","links":[],"slot_index":0},
      {"name":"CLIP","type":"CLIP","links":[],"slot_index":1},
      {"name":"VAE","type":"VAE","links":[],"slot_index":2}],
     ["realisticVisionV60B1_v51VAE.safetensors"])

node(3,"CLIPTextEncode",[420,10],[380,120],
     [{"name":"clip","type":"CLIP","link":None}],
     [{"name":"CONDITIONING","type":"CONDITIONING","links":[],"slot_index":0}],
     ["highly detailed, sharp focus, realistic photograph, natural texture, fine detail"])

node(4,"CLIPTextEncode",[420,170],[380,120],
     [{"name":"clip","type":"CLIP","link":None}],
     [{"name":"CONDITIONING","type":"CONDITIONING","links":[],"slot_index":0}],
     ["blurry, soft, noise, film grain, jpeg artifacts, compression, oversharpened, halo, plastic skin"])

node(5,"UpscaleModelLoader",[40,490],[320,60],[],
     [{"name":"UPSCALE_MODEL","type":"UPSCALE_MODEL","links":[],"slot_index":0}],
     ["4x_NMKD-Siax_200k.pth"])

# UltimateSDUpscale: upscale_by=6.4 (1920w source -> ~12288). For 4K(3840w) source set 3.2.
# tiled_decode=True to survive 75MP VAE decode on 32GB.
node(6,"UltimateSDUpscale",[840,10],[380,640],
     [{"name":"image","type":"IMAGE","link":None},
      {"name":"model","type":"MODEL","link":None},
      {"name":"positive","type":"CONDITIONING","link":None},
      {"name":"negative","type":"CONDITIONING","link":None},
      {"name":"vae","type":"VAE","link":None},
      {"name":"upscale_model","type":"UPSCALE_MODEL","link":None}],
     [{"name":"IMAGE","type":"IMAGE","links":[],"slot_index":0}],
     [6.4, 0, "fixed", 18, 6.0, "dpmpp_2m", "karras",
      0.20, "Chess", 1024, 1024, 16, 32,
      "Band Pass", 1.0, 64, 8, 16,
      True, True])

# Force exact canvas 12288x6144 (lanczos). Overshoot -> downscale = crisp.
node(7,"ImageScale",[1260,10],[300,130],
     [{"name":"image","type":"IMAGE","link":None}],
     [{"name":"IMAGE","type":"IMAGE","links":[],"slot_index":0}],
     ["lanczos",12288,6144,"disabled"])

node(8,"SaveImage",[1600,10],[420,470],
     [{"name":"images","type":"IMAGE","link":None}],[],
     ["12288x6144_upscaled"])

def set_out(nid,slot,lid):
    for n in nodes:
        if n["id"]==nid: n["outputs"][slot]["links"].append(lid)
def set_in(nid,slot,lid):
    for n in nodes:
        if n["id"]==nid: n["inputs"][slot]["link"]=lid

for (s,ss,d,ds,t) in [(2,1,3,0,"CLIP"),(2,1,4,0,"CLIP"),(1,0,6,0,"IMAGE"),
    (2,0,6,1,"MODEL"),(3,0,6,2,"CONDITIONING"),(4,0,6,3,"CONDITIONING"),
    (2,2,6,4,"VAE"),(5,0,6,5,"UPSCALE_MODEL"),(6,0,7,0,"IMAGE"),(7,0,8,0,"IMAGE")]:
    l=link(s,ss,d,ds,t); set_out(s,ss,l); set_in(d,ds,l)

wf={"last_node_id":8,"last_link_id":_lid[0],"nodes":nodes,"links":links,
    "groups":[],"config":{},"extra":{},"version":0.4}
out="/sessions/determined-friendly-allen/mnt/outputs/comfyui_12288x6144_realistic_upscale.json"
json.dump(wf,open(out,"w"),indent=2)
d=json.load(open(out)); ids={n["id"] for n in d["nodes"]}; ok=all(L[1] in ids and L[3] in ids for L in d["links"])
print("nodes:",len(d["nodes"]),"links:",len(d["links"]),"links_ok:",ok)
