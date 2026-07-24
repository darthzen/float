#!/usr/bin/env python3
"""Fetch every ESA/Webb Picture of the Month (POTM) at the highest resolution offered.

Discovery walks https://esawebb.org/images/potm/page/N/ until a page adds no new ids,
then scrapes each image page for its download archive links. "Highest resolution" =
the first available of: original (fullsize tif) > publicationtiff > large jpg.

Two stages so the total download size is known before committing disk (the dev Mac
runs tight on space, and this repo lives in iCloud Drive which syncs everything):

  python3 scripts/fetch_potm.py discover      # -> _raw/potm/potm_manifest.json + size report
  python3 scripts/fetch_potm.py fetch         # resumable downloads (curl -C -) + manifest .md
  python3 scripts/fetch_potm.py fetch --max-gb 8   # stop before exceeding a budget
  python3 scripts/fetch_potm.py add weic2316a saturn1 …   # hand-picked non-POTM ids -> same
                                              # manifest + downloads (accepts ids or page URLs)

Licensing: ESA/Webb images are CC BY 4.0 — fine to redistribute with attribution; the
per-image credit line lands in potm_manifest.md (fold into CREDITS.md when any master
is actually shipped in a scene).
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

BASE = "https://esawebb.org"
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
OUT = os.path.join(REPO, "Float/Resources/Textures/_raw/potm")
MANIFEST = os.path.join(OUT, "potm_manifest.json")
UA = "Mozilla/5.0 (Float POTM fetcher; rick@theashfords.org)"
# djangoplicity archive formats, best first.
FORMAT_PRIORITY = ["original", "publicationtiff", "large", "publicationjpg"]


def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode("utf-8", "replace")


def head_size(url):
    req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return int(r.headers.get("Content-Length") or 0), r.url
    except urllib.error.HTTPError:
        return None, None


def scrape_entry(pid):
    """Scrape one image page -> manifest entry (title, credit, best archive URL, size)."""
    html = get(f"{BASE}/images/{pid}/")
    title = re.search(r"<h1[^>]*>\s*(.*?)\s*</h1>", html, re.S)
    title = re.sub(r"<[^>]+>", "", title.group(1)).strip() if title else pid
    credit = re.search(r"Credit:?\s*</?\w*>?\s*(.*?)</(?:p|div|td)>", html, re.S)
    credit = re.sub(r"<[^>]+>", "", credit.group(1)).strip() if credit else ""
    links = re.findall(r'href="((?:https?://[^"]+|/media)/archives/images/([a-z_]+)/[^"]+)"', html)
    by_fmt = {}
    for href, fmt in links:
        by_fmt.setdefault(fmt, href if href.startswith("http") else BASE + href)
    url = None
    for fmt in FORMAT_PRIORITY:
        if fmt in by_fmt:
            url = by_fmt[fmt]
            break
    if not url:
        return None
    size, final_url = head_size(url)
    if size is None:
        for fmt in FORMAT_PRIORITY:
            if fmt in by_fmt and by_fmt[fmt] != url:
                size, final_url = head_size(by_fmt[fmt])
                if size is not None:
                    url = by_fmt[fmt]
                    break
    return {"id": pid, "title": title, "credit": credit,
            "url": final_url or url, "bytes": size or 0}


def add(ids):
    """Append hand-picked image ids (or /images/<id>/ URLs) to the manifest."""
    with open(MANIFEST) as f:
        entries = json.load(f)
    known = {e["id"] for e in entries}
    added = 0
    for raw in ids:
        pid = raw.strip("/").split("/")[-1]
        if pid in known:
            log(f"skip {pid} (already in manifest)")
            continue
        e = scrape_entry(pid)
        if e is None:
            log(f"  !! {pid}: no archive links found, skipping")
            continue
        entries.append(e)
        known.add(pid)
        added += 1
        log(f"  + {pid}: {e['title'][:60]} — {e['bytes']/1e6:.0f} MB")
    with open(MANIFEST, "w") as f:
        json.dump(entries, f, indent=1)
    total = sum(e["bytes"] for e in entries)
    log(f"ADDED {added}, manifest now {len(entries)} images, {total/1e9:.2f} GB total")


def discover():
    ids, page = [], 1
    while True:
        try:
            html = get(f"{BASE}/images/potm/page/{page}/")
        except urllib.error.HTTPError as e:
            if e.code == 404:
                break
            raise
        found = [i for i in re.findall(r'href="/images/(potm\w+)/"', html) if i != "potm"]
        new = [i for i in dict.fromkeys(found) if i not in ids]
        if not new:
            break
        ids.extend(new)
        log(f"page {page}: {len(new)} new ids ({len(ids)} total)")
        page += 1

    entries = []
    for i, pid in enumerate(ids):
        e = scrape_entry(pid)
        if e is None:
            log(f"  !! {pid}: no archive links found, skipping")
            continue
        entries.append(e)
        log(f"  [{i+1}/{len(ids)}] {pid}: {e['title'][:60]} — {e['bytes']/1e6:.0f} MB")

    os.makedirs(OUT, exist_ok=True)
    with open(MANIFEST, "w") as f:
        json.dump(entries, f, indent=1)
    total = sum(e["bytes"] for e in entries)
    log(f"DISCOVERED {len(entries)} images, total {total/1e9:.2f} GB -> {MANIFEST}")


def fetch(max_gb=None):
    with open(MANIFEST) as f:
        entries = json.load(f)
    budget = (max_gb * 1e9) if max_gb else None
    spent = ok = skip = fail = 0
    for e in entries:
        ext = os.path.splitext(e["url"].split("?")[0])[1] or ".tif"
        dst = os.path.join(OUT, e["id"] + ext)
        if os.path.exists(dst) and os.path.getsize(dst) >= e["bytes"] > 0:
            skip += 1
            continue
        if budget is not None and spent + e["bytes"] > budget:
            log(f"budget reached ({spent/1e9:.2f} GB) — stopping before {e['id']}")
            break
        log(f"fetch {e['id']} ({e['bytes']/1e6:.0f} MB): {e['title'][:60]}")
        r = subprocess.run(["curl", "-sSL", "--fail", "--retry", "3", "-C", "-",
                            "-A", UA, "-o", dst, e["url"]])
        if r.returncode == 0:
            ok += 1
            spent += e["bytes"]
        else:
            fail += 1
            log(f"  !! curl exit {r.returncode} for {e['id']}")

    md = os.path.join(OUT, "potm_manifest.md")
    with open(md, "w") as f:
        f.write("# ESA/Webb Picture of the Month — fullsize originals\n\n"
                "Source: https://esawebb.org/images/potm/ — CC BY 4.0.\n\n"
                "| file | title | credit |\n|---|---|---|\n")
        for e in entries:
            ext = os.path.splitext(e["url"].split("?")[0])[1] or ".tif"
            f.write(f"| `{e['id']}{ext}` | {e['title']} | {e['credit']} |\n")
    log(f"DONE: {ok} fetched, {skip} already present, {fail} failed; credits -> {md}")
    return 1 if fail else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("stage", choices=["discover", "fetch", "add"])
    ap.add_argument("ids", nargs="*", help="image ids or page URLs (add stage)")
    ap.add_argument("--max-gb", type=float, default=None,
                    help="stop fetching before exceeding this many GB")
    args = ap.parse_args()
    if args.stage == "discover":
        discover()
        return 0
    if args.stage == "add":
        add(args.ids)
        return 0
    return fetch(args.max_gb)


if __name__ == "__main__":
    sys.exit(main())
