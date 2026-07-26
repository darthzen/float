#!/usr/bin/env python3
"""Add a per-image PREMIUM checkbox to triage.html.

Purpose: the app bundles ~100 MB of stereo HEIC per scene, so shipping every sky in the
initial download is the single biggest lever on install size. Flagging scenes as premium
marks them for a future purchasable pack — downloaded on demand rather than up front. This
page is where that call gets made, alongside the KEEP/REMOVE call.

Splices ONE marked <style>+<script> block before </body> and attaches a checkbox to every
`.card` at runtime, rather than rewriting each card's markup. Three reasons:
  - The 50 sky cards must stay byte-identical: KEEP/REMOVE marks live in browser
    localStorage keyed by `data-name`, and rewriting cards risks disturbing that.
  - Cards added later (the planet section, or a future re-render) get the checkbox for
    free — no need to keep two generators in sync.
  - It stays a single block to remove if the idea is dropped.

Premium marks are stored under their OWN localStorage key, independent of the REMOVE set, so
an image can be both kept and premium — which is the normal case.

Idempotent: re-running replaces its own marked block.
"""

import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
HTML = ROOT / "triage.html"

MARK_START = "<!-- PREMIUM:START -->"
MARK_END = "<!-- PREMIUM:END -->"

BLOCK = """<!-- PREMIUM:START -->
<style>
  /* The card is position:relative already, so the toggle can sit over the artwork.
     Top-LEFT deliberately: the REMOVE tag owns the top-right corner. */
  .premium-toggle { position:absolute; top:8px; left:8px; z-index:3;
                    display:flex; gap:6px; align-items:center; cursor:pointer;
                    background:#000000b3; color:#cfcfd6; border:1px solid #3a3a44;
                    border-radius:5px; padding:3px 8px;
                    font-size:10px; letter-spacing:.07em; text-transform:uppercase; }
  .premium-toggle:hover { background:#000000e0; }
  .premium-toggle input { accent-color:#e8a33d; margin:0; cursor:pointer; }
  /* Gold, not red: a premium flag must stay readable on a card that is ALSO marked
     REMOVE, and .card.removed greys and dims the artwork underneath. */
  .card.premium .premium-toggle { background:#e8a33d; color:#1a1408;
                                  border-color:#f0b95e; font-weight:700; }
  .card.premium .premium-toggle input { accent-color:#1a1408; }
  #premiumBox { display:flex; gap:12px; align-items:center; flex:1; }
  #premiumBox textarea { flex:1; height:64px; background:#101014; color:#e8a33d;
                         border:1px solid #333; border-radius:6px; padding:6px 8px;
                         font:12px ui-monospace, monospace; resize:none; }
  #premiumCount { min-width:104px; color:#e8a33d; font-weight:600; }
</style>
<script>
(function () {
  var PKEY = "float-triage-premium";
  var premium = new Set(JSON.parse(localStorage.getItem(PKEY) || "[]"));
  var cards = Array.prototype.slice.call(document.querySelectorAll(".card"));
  var onPage = new Set(cards.map(function (c) { return c.dataset.name; }));
  // Drop marks for images no longer on the page, same as the REMOVE set does.
  premium = new Set(Array.from(premium).filter(function (n) { return onPage.has(n); }));

  function syncPremium() {
    localStorage.setItem(PKEY, JSON.stringify(Array.from(premium)));
    var names = Array.from(premium).sort();
    document.getElementById("premiumCount").textContent =
      premium.size + " premium \\u00b7 " + (onPage.size - premium.size) + " in base";
    document.getElementById("premiumList").value = names.join("\\n");
  }

  cards.forEach(function (card) {
    var name = card.dataset.name;
    var label = document.createElement("label");
    label.className = "premium-toggle";
    var box = document.createElement("input");
    box.type = "checkbox";
    box.checked = premium.has(name);
    // The whole card has an onclick that toggles REMOVE. Without stopPropagation, ticking
    // "premium" would also mark the image for deletion — the exact opposite intent.
    label.addEventListener("click", function (e) { e.stopPropagation(); });
    box.addEventListener("change", function () {
      if (box.checked) { premium.add(name); } else { premium.delete(name); }
      card.classList.toggle("premium", box.checked);
      syncPremium();
    });
    label.appendChild(box);
    label.appendChild(document.createTextNode("Premium"));
    card.appendChild(label);
    card.classList.toggle("premium", box.checked);
  });

  var box = document.createElement("div");
  box.id = "premiumBox";
  box.innerHTML =
    '<div id="premiumCount"></div>' +
    '<textarea id="premiumList" readonly spellcheck="false"></textarea>' +
    '<button type="button" id="premiumCopy">Copy premium</button>' +
    '<button type="button" id="premiumSave">Save premium</button>' +
    '<button type="button" id="premiumClear">Clear premium</button>';
  var footer = document.querySelector("footer");
  footer.style.flexWrap = "wrap";
  footer.appendChild(box);

  document.getElementById("premiumCopy").addEventListener("click", function () {
    var t = document.getElementById("premiumList");
    t.select(); document.execCommand("copy");
  });
  document.getElementById("premiumSave").addEventListener("click", function () {
    var blob = new Blob([document.getElementById("premiumList").value + "\\n"],
                        { type: "text/plain" });
    var a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = "triage_premium.txt";
    a.click();
  });
  document.getElementById("premiumClear").addEventListener("click", function () {
    if (!confirm("Clear all premium flags?")) { return; }
    premium.clear();
    document.querySelectorAll(".card.premium").forEach(function (c) {
      c.classList.remove("premium");
      var cb = c.querySelector(".premium-toggle input");
      if (cb) { cb.checked = false; }
    });
    syncPremium();
  });

  syncPremium();
})();
</script>
<!-- PREMIUM:END -->
"""


def main():
    html = HTML.read_text()

    if MARK_START in html:
        html = re.sub(
            re.escape(MARK_START) + r".*?" + re.escape(MARK_END) + r"\n?",
            # lambda, not the string itself: re.sub parses backslash escapes in a literal
            # replacement, and this block legitimately contains \u sequences (JS string
            # escapes), which raises "bad escape \u".
            lambda _m: BLOCK, html, flags=re.DOTALL)
        action = "replaced"
    else:
        # After the existing </script> and before </body>, so it runs once the page's own
        # toggle()/sync() are already defined and every card is in the DOM.
        html = html.replace("</body>", BLOCK + "</body>", 1)
        action = "inserted"

    HTML.write_text(html)
    print(f"{action} premium-flag block in triage.html")


if __name__ == "__main__":
    main()
