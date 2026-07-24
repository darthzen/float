#!/usr/bin/env python3
"""Remove scenes from the shipping library (the triage-page 'remove' batch).

Per scene: deletes Backdrop/<name>.heic + Thumbnails/<name>.jpg + any local
_raw/potm_sr/<pid>.png, drops the SpatialImageEnvironment.catalog entry, drops the
deepsky_auto.json row, removes single-line MANIFEST tuples in deepsky_pipeline.py /
process_backdrops.py, and records the id in upscale/pruned_scenes.json so a future
potm_auto_manifest.py regeneration cannot resurrect it. NEVER touches the originals
archive on /Volumes/Logic Pro — pruned scenes can always be rebuilt from there.

Run:  python3 scripts/prune_scenes.py spatial_potm2603a potm2211a ...
      python3 scripts/prune_scenes.py --file removed.txt   # one name per line
Then: python3 scripts/make_triage_page.py                  # refresh the triage page
"""
import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
BACKDROP = os.path.join(REPO, "Float/Resources/Textures/Backdrop")
THUMBS = os.path.join(BACKDROP, "Thumbnails")
SR_DIR = os.path.join(REPO, "Float/Resources/Textures/_raw/potm_sr")
CATALOG = os.path.join(REPO, "Float/Immersive/SpatialImageEnvironment.swift")
AUTO = os.path.join(REPO, "upscale/deepsky_auto.json")
PRUNED = os.path.join(REPO, "upscale/pruned_scenes.json")
PY_MANIFESTS = [os.path.join(REPO, "upscale/deepsky_pipeline.py"),
                os.path.join(REPO, "upscale/process_backdrops.py")]


def rm(path, log):
    if os.path.exists(path):
        os.remove(path)
        log.append(f"  rm {os.path.relpath(path, REPO)}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("names", nargs="*")
    ap.add_argument("--file", help="file with one scene name per line")
    args = ap.parse_args()
    names = list(args.names)
    if args.file:
        names += [ln.strip() for ln in open(args.file) if ln.strip()]
    names = ["spatial_" + n if not n.startswith("spatial_") else n for n in names]
    if not names:
        ap.error("no scene names given")

    cat = open(CATALOG).read()
    auto = json.load(open(AUTO))
    pruned = json.load(open(PRUNED)) if os.path.exists(PRUNED) else []
    pys = {p: open(p).read() for p in PY_MANIFESTS}

    for name in names:
        pid = name.removeprefix("spatial_")
        log = [f"{name}:"]
        rm(os.path.join(BACKDROP, f"{name}.heic"), log)
        rm(os.path.join(THUMBS, f"{name}.jpg"), log)
        rm(os.path.join(SR_DIR, f"{pid}.png"), log)

        cat, n = re.subn(rf'[ \t]*\.init\(name: "{re.escape(name)}",[^\n]*\n', "", cat)
        if n:
            log.append(f"  catalog entry removed ({n})")
        before = len(auto)
        auto = [r for r in auto if r["name"] != name]
        if len(auto) != before:
            log.append("  deepsky_auto.json row removed")
        for p in pys:
            pys[p], n = re.subn(rf'[ \t]*\("{re.escape(name)}",[^\n]*\n', "", pys[p])
            if n:
                log.append(f"  {os.path.basename(p)} MANIFEST row removed")
        if pid not in pruned:
            pruned.append(pid)
        print("\n".join(log))

    open(CATALOG, "w").write(cat)
    json.dump(auto, open(AUTO, "w"), indent=1)
    json.dump(sorted(pruned), open(PRUNED, "w"), indent=1)
    for p, src in pys.items():
        open(p, "w").write(src)
    print(f"\n{len(names)} scene(s) pruned; ids recorded in upscale/pruned_scenes.json")
    print("Originals remain in the archive on /Volumes/Logic Pro (untouched).")


if __name__ == "__main__":
    sys.exit(main())
