#!/usr/bin/env python3
"""Splice the planet-geometry test renders into triage.html.

Surgical on purpose. `make_triage_page.py` regenerates the whole file, which would wipe
nothing on disk but WOULD reshuffle the card set — and Rick's KEEP/REMOVE marks live in
browser localStorage keyed by `data-name`, so the page has to keep its existing cards
byte-identical for those marks to survive. This only adds (or replaces) one section.

Idempotent: re-run it after re-rendering previews and it replaces its own section rather
than stacking a second copy.
"""

import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
HTML = ROOT / "triage.html"
PREV = ROOT / "upscale" / "planet_prev"

MARK_START = "<!-- PLANETS:START -->"
MARK_END = "<!-- PLANETS:END -->"

# name -> (title, note). The angular figures are the honest-detail limits worked out from
# required map width = 360 x 34 px/deg x R/(d-R): past these the body is being magnified
# beyond what its source map actually resolves.
CARDS = [
    ("saturn",       "Saturn — live lighting",
     "8192 map (4096 real under SR) · honest to ~29&deg; · rings span 2.27 R"),
    ("saturn_baked", "Saturn — ring shadow baked",
     "Cycles bake at 8192, globe unlit &middot; <b>should look near-identical to the card "
     "above — that is the pass condition</b>, it means the bake reproduced the ray-traced "
     "lighting faithfully (measured: mean diff 0.25/255, 2.7% of pixels). The difference "
     "only appears IN THE APP, where the live-lit version loses the ring shadow entirely "
     "because RealityKit cannot cast it &middot; caveat: the globe's shadow ACROSS THE RINGS "
     "is live Cycles here and will NOT survive (ring UV is 1-D, nothing to bake into)"),
    ("jupiter",      "Jupiter &mdash; Cassini + Juno",
     "14400 REAL (Björn Jónsson) vs 4096 for the artist texture it replaces &middot; honest "
     "to ~62&deg;, the sharpest body here &middot; spun to put the Great Red Spot on the "
     "visible face &middot; graded +35% sat, +0.15 contrast &middot; poles are partly "
     "synthetic where Juno data was blended in &middot; ⚠ redistribution needs a call, "
     "see CREDITS.md"),
    ("iapetus",      "Iapetus &mdash; colour mosaic",
     "11741 real Cassini/Voyager colour &middot; honest to ~59&deg; &middot; the two-tone "
     "split (bright trailing side vs dark Cassini Regio) is the point &middot; known "
     "defects: smeared poles, mosaic seams, green cast near the terminator"),
    ("venus",        "Venus",
     "8192 real (SSS surface) &middot; honest to ~47&deg; &middot; "
     "retrograde, so north reads inverted"),
]


def card(name, title, note):
    return (
        f'<figure class="card" data-name="planet_{name}" onclick="toggle(this)">'
        f'<div class="lbl">geometry test</div>'
        f'<img loading="lazy" src="upscale/planet_prev/{name}.jpg" alt="{name}">'
        f'<div class="tag">REMOVE</div>'
        f'<figcaption><b>{title}</b><br>{note}</figcaption></figure>'
    )


def main():
    html = HTML.read_text()

    present = [c for c in CARDS if (PREV / f"{c[0]}.jpg").exists()]
    missing = [c[0] for c in CARDS if not (PREV / f"{c[0]}.jpg").exists()]
    if missing:
        print(f"warning: no preview for {', '.join(missing)} — card(s) skipped")
    if not present:
        print("nothing to insert; run render_planets.py --preview first")
        return

    section = (
        f"{MARK_START}\n"
        f'<h2>Planets &mdash; geometry tests <span class="n">({len(present)})</span></h2>'
        f'<div class="grid">\n'
        + "\n".join(card(*c) for c in present)
        + f"\n</div>\n{MARK_END}\n"
    )

    if MARK_START in html:
        html = re.sub(
            re.escape(MARK_START) + r".*?" + re.escape(MARK_END) + r"\n?",
            section, html, flags=re.DOTALL)
        action = "replaced"
    else:
        # Before the footer, so the planets land at the end of the scrollable card list
        # rather than above the sky sections Rick is part-way through triaging.
        html = html.replace("<footer>", section + "<footer>", 1)
        action = "inserted"

    HTML.write_text(html)
    print(f"{action} {len(present)} planet card(s) in triage.html")


if __name__ == "__main__":
    main()
