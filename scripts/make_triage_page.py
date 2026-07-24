#!/usr/bin/env python3
"""Generate triage.html (repo root): every Backdrop thumbnail on one page, click to
mark scenes for removal, export the marked list. For the manual keep/prune pass over
the 84-scene library. Selection persists in localStorage; thumbnails are referenced
by relative path (not embedded) so re-rendered scenes show current pixels on reload.

Run:  python3 scripts/make_triage_page.py   # then open triage.html in a browser
"""
import html as html_mod
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
THUMBS = os.path.join(REPO, "Float/Resources/Textures/Backdrop/Thumbnails")
THUMBS_REL = "Float/Resources/Textures/Backdrop/Thumbnails"
CATALOG = os.path.join(REPO, "Float/Immersive/SpatialImageEnvironment.swift")
AUTO = os.path.join(REPO, "upscale/deepsky_auto.json")
OUT = os.path.join(REPO, "triage.html")
# Original-master previews for the POTM cards, so render quality can be judged
# against the source. Generated from the archive drive; skipped when unmounted.
ARCHIVE_POTM = "/Volumes/Logic Pro/Float Originals Archive/potm"
ORIG_DIR = os.path.join(REPO, "triage_originals")
ORIG_REL = "triage_originals"

GROUPS = [  # (label, predicate on scene name) — first match wins
    ("Grounded", ("spatial_rogland", "spatial_dikhololo", "spatial_paranal",
                  "spatial_lasilla")),
    ("All-sky maps (SPHEREx / unWISE)", ("spatial_spherex", "spatial_unwise")),
    ("Deep space (Shutterstock + star map)",
     ("spatial_dual_nebula", "spatial_blue_filaments", "spatial_teal_orange",
      "spatial_dark_dust", "spatial_pale_haze", "spatial_deep_star_map")),
    ("Deep-sky masters (hand-tuned)",
     ("spatial_carina_mystic", "spatial_m16_pillars", "spatial_m8_lagoon",
      "spatial_s106_angel", "spatial_m104_sombrero", "spatial_m106_spiral",
      "spatial_ngc4631_whale", "spatial_m31_andromeda")),
    ("POTM / hand-picked (auto-placed)", ()),          # catch-all
]


def ensure_original_thumbs(pids):
    """Make triage_originals/<pid>.jpg (512px long side) from the archived masters.
    Returns the set of pids that have a preview available."""
    from PIL import Image
    Image.MAX_IMAGE_PIXELS = None
    have = set()
    missing = []
    for pid in pids:
        dst = os.path.join(ORIG_DIR, f"{pid}.jpg")
        if os.path.exists(dst):
            have.add(pid)
            continue
        src = next((os.path.join(ARCHIVE_POTM, pid + e)
                    for e in (".tif", ".png", ".jpg")
                    if os.path.exists(os.path.join(ARCHIVE_POTM, pid + e))), None)
        if not src:
            missing.append(pid)
            continue
        os.makedirs(ORIG_DIR, exist_ok=True)
        im = Image.open(src).convert("RGB")
        im.thumbnail((512, 512), Image.LANCZOS)
        im.save(dst, quality=85)
        have.add(pid)
    if missing:
        print(f"no archive original for: {', '.join(missing)}"
              + ("" if os.path.isdir(ARCHIVE_POTM) else "  (archive not mounted)"))
    return have


def titles_from_catalog():
    t = {}
    src = open(CATALOG).read()
    for m in re.finditer(r'\.init\(name:\s*"([^"]+)",\s*title:\s*"([^"]+)"', src):
        t[m.group(1)] = m.group(2)
    return t


def main():
    titles = titles_from_catalog()
    if os.path.exists(AUTO):
        for r in json.load(open(AUTO)):
            titles.setdefault(r["name"], r.get("title", ""))
    scenes = sorted(os.path.splitext(f)[0] for f in os.listdir(THUMBS)
                    if f.endswith(".jpg"))
    grouped = {label: [] for label, _ in GROUPS}
    for s in scenes:
        for label, prefixes in GROUPS:
            if not prefixes or any(s.startswith(p) for p in prefixes):
                grouped[label].append(s)
                break

    potm_label = GROUPS[-1][0]
    with_orig = ensure_original_thumbs(
        [s.removeprefix("spatial_") for s in grouped[potm_label]])

    cards = []
    for label, _ in GROUPS:
        if not grouped[label]:
            continue
        cards.append(f'<h2>{html_mod.escape(label)} '
                     f'<span class="n">({len(grouped[label])})</span></h2>'
                     f'<div class="grid">')
        for s in grouped[label]:
            title = html_mod.escape(titles.get(s, ""))
            pid = s.removeprefix("spatial_")
            orig = (f'<div class="lbl">master</div>'
                    f'<img loading="lazy" class="orig" src="{ORIG_REL}/{pid}.jpg" alt="">'
                    if label == potm_label and pid in with_orig else "")
            lbl = '<div class="lbl">render</div>' if orig else ""
            cards.append(
                f'<figure class="card" data-name="{s}" onclick="toggle(this)">'
                f'{lbl}<img loading="lazy" src="{THUMBS_REL}/{s}.jpg" alt="{s}">'
                f'{orig}<div class="tag">REMOVE</div>'
                f'<figcaption><b>{pid}</b>'
                f'{"<br>" + title if title else ""}</figcaption></figure>')
        cards.append("</div>")

    page = """<!doctype html><html><head><meta charset="utf-8">
<title>Float backdrop triage</title>
<style>
  :root { color-scheme: dark; }
  body { background:#101014; color:#ddd; margin:0 0 130px 0;
         font:14px/1.4 -apple-system, system-ui, sans-serif; }
  header { position:sticky; top:0; background:#101014e6; backdrop-filter:blur(6px);
           padding:12px 20px; z-index:2; border-bottom:1px solid #26262e; }
  h1 { font-size:17px; margin:0; } h1 small { color:#888; font-weight:400; }
  h2 { margin:26px 20px 10px; font-size:15px; color:#bbb; } h2 .n { color:#666; }
  .grid { display:grid; grid-template-columns:repeat(auto-fill,minmax(300px,1fr));
          gap:12px; padding:0 20px; }
  .card { position:relative; margin:0; cursor:pointer; border-radius:8px;
          overflow:hidden; background:#17171c; outline:2px solid transparent; }
  .card img { width:100%; aspect-ratio:2/1; object-fit:cover; display:block; }
  .card img.orig { aspect-ratio:auto; max-height:170px; object-fit:contain;
                   background:#000; border-top:1px solid #26262e; }
  .card .lbl { font-size:10px; letter-spacing:.08em; text-transform:uppercase;
               color:#777; padding:3px 9px 2px; background:#131318; }
  .card figcaption { padding:6px 9px 8px; color:#aaa; }
  .card figcaption b { color:#ddd; font-weight:600; }
  .card .tag { position:absolute; top:8px; right:8px; background:#d33;
               color:#fff; font-weight:700; font-size:12px; padding:2px 8px;
               border-radius:4px; display:none; }
  .card.removed { outline-color:#d33; }
  .card.removed img { filter:grayscale(.9) brightness(.45); }
  .card.removed .tag { display:block; }
  footer { position:fixed; bottom:0; left:0; right:0; background:#17171cf2;
           border-top:1px solid #26262e; padding:10px 20px;
           display:flex; gap:14px; align-items:center; }
  footer textarea { flex:1; height:64px; background:#101014; color:#e88;
                    border:1px solid #333; border-radius:6px; padding:6px 8px;
                    font:12px ui-monospace, monospace; resize:none; }
  footer button { background:#2a2a33; color:#ddd; border:1px solid #444;
                  border-radius:6px; padding:8px 14px; cursor:pointer; }
  footer button:hover { background:#34343e; }
  #count { min-width:110px; color:#e88; font-weight:600; }
</style></head><body>
<header><h1>Float backdrop triage <span id="stats"></span> <small>— click a card to
mark it for removal; selection persists in this browser</small></h1></header>
__CARDS__
<footer>
  <div id="count"></div>
  <textarea id="list" readonly spellcheck="false"></textarea>
  <button onclick="copyList()">Copy list</button>
  <button onclick="saveList()">Save list</button>
  <button onclick="clearAll()">Clear all</button>
</footer>
<script>
const KEY = "float-triage-removed";
let removed = new Set(JSON.parse(localStorage.getItem(KEY) || "[]"));
// Drop marks for scenes no longer on the page (already pruned in an earlier batch).
const onPage = new Set([...document.querySelectorAll(".card")].map(c => c.dataset.name));
removed = new Set([...removed].filter(n => onPage.has(n)));
document.querySelectorAll(".card").forEach(c => {
  if (removed.has(c.dataset.name)) c.classList.add("removed");
});
function sync() {
  localStorage.setItem(KEY, JSON.stringify([...removed]));
  document.getElementById("count").textContent =
    removed.size + " marked · " + (onPage.size - removed.size) + " kept";
  document.getElementById("list").value = [...removed].sort().join("\\n");
}
function saveList() {
  const blob = new Blob([document.getElementById("list").value + "\\n"],
                        {type: "text/plain"});
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = "triage_removed.txt";
  a.click();
}
function toggle(c) {
  const n = c.dataset.name;
  removed.has(n) ? removed.delete(n) : removed.add(n);
  c.classList.toggle("removed");
  sync();
}
function copyList() {
  const t = document.getElementById("list");
  t.select(); document.execCommand("copy");
}
function clearAll() {
  if (!confirm("Clear all marks?")) return;
  removed.clear();
  document.querySelectorAll(".card.removed").forEach(c => c.classList.remove("removed"));
  sync();
}
sync();
</script></body></html>"""
    with open(OUT, "w") as f:
        f.write(page.replace("__CARDS__", "\n".join(cards)))
    print(f"{len(scenes)} scenes -> {OUT}")


if __name__ == "__main__":
    main()
