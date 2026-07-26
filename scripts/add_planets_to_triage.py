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
     "Cycles bake at 8192, globe unlit &middot; the shadow ON THE GLOBE is baked in and "
     "survives into RealityKit &middot; the globe's shadow ACROSS THE RINGS is live Cycles "
     "here and will NOT appear in the app yet (ring UV is 1-D, nothing to bake into)"),
    ("jupiter",      "Jupiter",
     "8192 map (4096 real under SR) · honest to ~29&deg;"),
    ("iapetus",      "Iapetus &mdash; mono mosaic",
     "8192 from the Cassini/Voyager mono mosaic &middot; honest to ~47&deg; &middot; "
     "the 11741 colour map would reach ~59&deg; but has smeared poles and seams"),
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
