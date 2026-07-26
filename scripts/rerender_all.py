#!/usr/bin/env python3
"""Full library re-render — every scene, every fix, one command.

Why this exists: the fixes for the device round-6/7 defects (USDU tile banding, the
180deg seam, the hard footprint box, blobby background galaxies, the pole whirlpool,
the m8_lagoon mirror triptych, the m31 twin subject, the milky surround, and the
stereo disparity terracing) all landed in code while the shipped assets stayed on the
OLD renders. Nothing in the headset had any fix in it. This walks the whole library
back through the pipeline so the assets and the code finally agree.

Two phases, because the library is built by two different pipelines:

  Phase 1  deep-sky scenes  (upscale/deepsky_pipeline.py)
           Flat astrophoto masters -> diffusion 360 sky -> RealESRGAN to 12288 ->
           pole soften -> master re-composite -> stereo -> pack. The expensive one:
           two pod round-trips per scene. Sky-recipe caches are keyed by SKY_RECIPE,
           so a scene already rendered at the current recipe re-runs only the cheap
           tail (SR onward), not the diffusion.

  Phase 2  backdrop scenes  (upscale/process_backdrops.py)
           Imported panoramas, Shutterstock deep-space plates, SPHEREx/unWISE
           all-skies. These never touch sky360 — but they DO go through
           stereo_synth, so they need re-packing to pick up the sub-pixel disparity
           fix. That is the one that removes the latitude arcs, and it is the reason
           this phase is in the list at all.

Progress is written both to the terminal (live status line + per-stage detail) and to
a timestamped log file, so leaving it running and checking back later works fine.
State is journalled after every scene: interrupting with Ctrl-C and re-running picks
up where it stopped instead of starting over.

Run:
    python3 scripts/rerender_all.py                  # everything, resumable
    python3 scripts/rerender_all.py --dry-run        # show the plan, do nothing
    python3 scripts/rerender_all.py --phase 1        # deep-sky only
    python3 scripts/rerender_all.py --only spatial_m8_lagoon
    python3 scripts/rerender_all.py --restart        # ignore previous state
    python3 scripts/rerender_all.py --quality 0.92   # HEIC lossy quality
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
UPSCALE = os.path.join(REPO, "upscale")
BACKDROP = os.path.join(REPO, "Float/Resources/Textures/Backdrop")
LOGDIR = os.path.join(REPO, "upscale", "logs")

# Scratch (stage caches + per-scene temp) goes to an external volume when one is
# mounted: the repo sits on an iCloud-backed volume that runs near full, and a scene
# needs ~1 GB of temp at once for the mono equirect plus two 12288x6144 eye PNGs.
SCRATCH_CANDIDATES = ["/Volumes/Logic Pro"]
IN_REPO_CACHE = os.path.join(REPO, "Float/Resources/Textures/_raw/_sky_cache")


def pick_scratch(explicit=None):
    """(cache_dir, tmp_dir, label) — external scratch if usable, else in-repo."""
    for base in ([explicit] if explicit else SCRATCH_CANDIDATES):
        if base and os.path.isdir(base) and os.access(base, os.W_OK):
            root = os.path.join(base, "FloatScratch")
            return (os.path.join(root, "sky_cache"), os.path.join(root, "tmp"), base)
    return (IN_REPO_CACHE, None, "in-repo (no scratch volume)")

# Nominal per-scene wall clock, used only for the ETA before real timings exist.
NOMINAL = {1: 6 * 60, 2: 2 * 60}

C = {"dim": "\x1b[2m", "b": "\x1b[1m", "g": "\x1b[32m", "r": "\x1b[31m",
     "y": "\x1b[33m", "c": "\x1b[36m", "0": "\x1b[0m"}
TTY = sys.stdout.isatty()
if not TTY:
    C = {k: "" for k in C}

# Child stdout lines matching these are pipeline noise, not progress.
NOISE = ("tar: Removing leading", "warning: failed to translate")


def hms(sec):
    sec = int(max(0, sec))
    h, m, s = sec // 3600, (sec % 3600) // 60, sec % 60
    return f"{h}h{m:02d}m" if h else (f"{m}m{s:02d}s" if m else f"{s}s")


class Screen:
    """Terminal output with one live status line pinned to the bottom."""

    def __init__(self, logpath):
        self.log = open(logpath, "a", buffering=1)
        self.status = ""

    def _clear(self):
        if TTY and self.status:
            sys.stdout.write("\x1b[2K\r")
            sys.stdout.flush()

    def line(self, text="", to_log=True):
        self._clear()
        print(text)
        if to_log:
            self.log.write(_strip_ansi(text) + "\n")
        self.redraw()

    def set_status(self, text):
        self.status = text
        self.redraw()

    def redraw(self):
        if TTY and self.status:
            w = shutil.get_terminal_size((100, 24)).columns
            s = self.status
            if len(_strip_ansi(s)) > w - 1:
                s = s[: w - 2] + "…"
            sys.stdout.write("\x1b[2K\r" + s)
            sys.stdout.flush()

    def done(self):
        self._clear()
        self.status = ""
        self.log.close()


def _strip_ansi(s):
    out, i = [], 0
    while i < len(s):
        if s[i] == "\x1b":
            j = s.find("m", i)
            i = len(s) if j < 0 else j + 1
        else:
            out.append(s[i])
            i += 1
    return "".join(out)


def bar(done, total, width=30):
    filled = 0 if not total else int(round(width * done / total))
    return "█" * filled + "░" * (width - filled)


def load_manifests():
    """Scene lists, imported from the pipelines themselves so this never drifts."""
    sys.path.insert(0, UPSCALE)
    sys.path.insert(0, os.path.join(REPO, "scripts"))
    import deepsky_pipeline as dp
    import process_backdrops as pb
    from sky360 import SKY_RECIPE
    phase1 = [(n, k) for (n, _rel, k, _p) in dp.MANIFEST]
    phase2 = [(n, c) for (n, _src, c, _e) in pb.MANIFEST]
    return phase1, phase2, SKY_RECIPE


def stale_cache(recipe, sky_cache):
    """Stage files in the sky cache that the CURRENT recipe can never reuse."""
    if not os.path.isdir(sky_cache):
        return [], 0
    keep = f"_{recipe}_"
    files, total = [], 0
    for f in os.listdir(sky_cache):
        p = os.path.join(sky_cache, f)
        if f.startswith(".") or not os.path.isfile(p) or keep in f:
            continue
        files.append(p)
        total += os.path.getsize(p)
    return files, total


def preflight(scr, need_pod, n1, n2, recipe, sky_cache, scratch_label):
    ok = True

    def check(label, good, detail):
        nonlocal ok
        mark = f"{C['g']}✓{C['0']}" if good else f"{C['r']}✗{C['0']}"
        scr.line(f"    {mark} {label:<20} {detail}")
        ok = ok and good

    def warn(label, detail):
        scr.line(f"    {C['y']}!{C['0']} {label:<20} {detail}")

    pod = ""
    if need_pod:
        r = subprocess.run(["kubectl", "get", "pods", "-n", "ai", "-l", "app=comfyui",
                            "--no-headers", "-o", "custom-columns=:metadata.name"],
                           capture_output=True, text=True)
        pod = r.stdout.strip().split("\n")[0] if r.returncode == 0 else ""
        check("comfyui pod", bool(pod), pod or "NOT FOUND — the diffusion stages will fail")
    else:
        scr.line(f"    {C['dim']}·{C['0']} comfyui pod        not needed for this selection")

    sw = shutil.which("swift")
    check("swift", bool(sw), sw or "NOT FOUND — pack_spatial.swift cannot run")

    # Sized from what the run actually writes, not a round number: each deep-sky scene
    # leaves ~52 MB of stage cache (outpaint + the 12288 SR), and any scene needs ~1 GB
    # of scratch at once for the mono equirect plus two eye PNGs at 12288x6144.
    need = (0.052 * n1) + (1.5 if (n1 or n2) else 0)
    scratch_free = shutil.disk_usage(os.path.dirname(sky_cache.rstrip("/")) 
                                     if os.path.isdir(os.path.dirname(sky_cache.rstrip("/")))
                                     else REPO).free / 1e9
    check("scratch", scratch_free > need,
          f"{scratch_label}  —  {scratch_free:.1f} GB free, ~{need:.1f} GB needed")

    # The HEICs themselves always land in the repo, whatever the scratch setting.
    repo_free = shutil.disk_usage(REPO).free / 1e9
    out_need = 0.035 * (n1 + n2)
    check("repo volume", repo_free > out_need,
          f"{repo_free:.1f} GB free, ~{out_need:.1f} GB of HEICs to write")

    files, total = stale_cache(recipe, sky_cache)
    if files:
        warn("stale cache", f"{len(files)} pre-{recipe} stage file(s), {total / 1e9:.1f} GB "
                            f"— reclaim with {C['b']}--clean-cache{C['0']}")

    check("backdrop dir", os.path.isdir(BACKDROP), BACKDROP)

    # Master source dirs may be symlinks onto the scratch volume (potm was moved there
    # to free the repo volume). A dangling one fails per-scene, deep into the run, as a
    # bare FileNotFoundError — check it up front where it is one obvious line.
    raw = os.path.join(REPO, "Float/Resources/Textures/_raw")
    for sub in ("potm", "potm_sr", "deepsky"):
        p = os.path.join(raw, sub)
        live = os.path.isdir(p) and bool(os.listdir(p))
        where = f" -> {os.path.realpath(p)}" if os.path.islink(p) else ""
        check(f"masters/{sub}", live,
              ("ok" if live else "MISSING or empty — is the scratch volume mounted?") + where)
    return ok


def run_scene(scr, name, phase, quality, overall, totals, t_start, extra_env):
    """Run one scene as a child process, streaming its stages. Returns (ok, seconds)."""
    script = "deepsky_pipeline.py" if phase == 1 else "process_backdrops.py"
    cmd = [sys.executable, os.path.join(UPSCALE, script), "--only", name, "--force"]
    env = dict(os.environ, FLOAT_HEIC_QUALITY=str(quality), PYTHONUNBUFFERED="1",
               **extra_env)

    t0 = time.time()
    stage = "starting"

    def status():
        done, total = overall
        pct = 0 if not total else 100 * done / total
        elapsed = time.time() - t_start
        per = totals["mean"](phase)
        eta = (total - done) * per
        return (f"  {C['c']}[{bar(done, total)}]{C['0']} {done}/{total} {pct:3.0f}%  "
                f"elapsed {hms(elapsed)}  eta {hms(eta)}  "
                f"{C['dim']}▸ {name}: {stage}{C['0']}")

    scr.set_status(status())
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                         text=True, bufsize=1, env=env, cwd=REPO)
    tail = []
    for raw in p.stdout:
        line = raw.rstrip("\n")
        if not line.strip() or any(n in line for n in NOISE):
            continue
        tail.append(line)
        tail[:] = tail[-25:]
        scr.log.write(line + "\n")
        # "[HH:MM:SS]   spatial_x: outpaint (119s)" -> "outpaint (119s)"
        msg = line.split("] ", 1)[1] if line.startswith("[") and "] " in line else line
        msg = msg.strip()
        if msg.startswith(name + ":"):
            msg = msg[len(name) + 1:].strip()
        if msg.startswith("==="):
            continue
        stage = msg
        scr.line(f"    {C['dim']}{time.strftime('%H:%M:%S')}{C['0']}  {msg}", to_log=False)
        scr.set_status(status())
    rc = p.wait()
    secs = time.time() - t0

    heic = os.path.join(BACKDROP, f"{name}.heic")
    if rc == 0 and os.path.exists(heic):
        mb = os.path.getsize(heic) / 1e6
        scr.line(f"  {C['g']}✓{C['0']} {name}  {hms(secs)}  →  {mb:.1f} MB")
        return True, secs, mb
    scr.line(f"  {C['r']}✗ {name} FAILED (exit {rc}){C['0']}")
    for t in tail[-8:]:
        scr.line(f"      {C['dim']}{t}{C['0']}")
    return False, secs, 0.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="print the plan and exit")
    ap.add_argument("--phase", choices=["1", "2", "all"], default="all")
    ap.add_argument("--only", help="one scene name (implies its phase)")
    ap.add_argument("--restart", action="store_true", help="ignore previous state")
    ap.add_argument("--quality", type=float, default=0.95,
                    help="HEIC lossy quality passed as FLOAT_HEIC_QUALITY (default 0.95)")
    ap.add_argument("--clean-cache", action="store_true",
                    help="delete sky-cache stage files from older recipes, then continue")
    ap.add_argument("--scratch", metavar="DIR",
                    help="volume for stage caches and per-scene temp files "
                         "(default: an external scratch volume if one is mounted)")
    ap.add_argument("--no-scratch", action="store_true",
                    help="keep caches and temp inside the repo")
    args = ap.parse_args()

    sky_cache, tmp_dir, scratch_label = (
        (IN_REPO_CACHE, None, "in-repo (--no-scratch)") if args.no_scratch
        else pick_scratch(args.scratch))
    state_path = os.path.join(sky_cache, ".rerender_state.json")
    extra_env = {"FLOAT_SKY_CACHE": sky_cache}
    if tmp_dir:
        extra_env["TMPDIR"] = tmp_dir

    phase1, phase2, recipe = load_manifests()
    plan = []
    if args.phase in ("1", "all"):
        plan += [(1, n, k) for n, k in phase1]
    if args.phase in ("2", "all"):
        plan += [(2, n, k) for n, k in phase2]
    if args.only:
        plan = [r for r in plan if r[1] == args.only]
        if not plan:
            print(f"no scene named {args.only}")
            return 2

    os.makedirs(LOGDIR, exist_ok=True)
    os.makedirs(sky_cache, exist_ok=True)
    if tmp_dir:
        os.makedirs(tmp_dir, exist_ok=True)
    logpath = os.path.join(LOGDIR, f"rerender_{time.strftime('%Y%m%d_%H%M%S')}.log")

    state = {}
    if os.path.exists(state_path) and not args.restart:
        try:
            state = json.load(open(state_path))
        except Exception:
            state = {}
    # A scene counts as done only if it finished at THIS sky recipe and quality.
    def is_done(n):
        s = state.get(n)
        return bool(s and s.get("ok") and s.get("recipe") == recipe
                    and abs(s.get("quality", -1) - args.quality) < 1e-9)

    todo = [r for r in plan if not is_done(r[1])]
    skipped = len(plan) - len(todo)

    scr = Screen(logpath)
    n1 = sum(1 for r in todo if r[0] == 1)
    n2 = sum(1 for r in todo if r[0] == 2)
    est = n1 * NOMINAL[1] + n2 * NOMINAL[2]

    scr.line("")
    scr.line(f"{C['b']}══ Float — full library re-render ══{C['0']}")
    scr.line("")
    scr.line(f"  sky recipe          {C['b']}{recipe}{C['0']}")
    scr.line(f"  HEIC quality        {C['b']}{args.quality}{C['0']}   (FLOAT_HEIC_QUALITY)")
    scr.line(f"  phase 1  deep-sky   {n1:>3} scene(s)   diffusion + SR + stereo + pack")
    scr.line(f"  phase 2  backdrops  {n2:>3} scene(s)   stereo + pack (SR cached)")
    if skipped:
        scr.line(f"  already done        {skipped:>3} scene(s)   {C['dim']}"
                 f"(--restart to redo){C['0']}")
    scr.line(f"  estimated           {C['b']}~{hms(est)}{C['0']}   {C['dim']}"
             f"(nominal; refined from real timings as it goes){C['0']}")
    scr.line(f"  scratch             {sky_cache}")
    scr.line(f"  log                 {logpath}")
    if args.clean_cache:
        files, total = stale_cache(recipe, sky_cache)
        for p in files:
            try:
                os.unlink(p)
            except OSError:
                pass
        scr.line(f"  {C['g']}cleaned{C['0']}             {len(files)} stale stage file(s), "
                 f"{total / 1e9:.1f} GB reclaimed")

    scr.line("")
    scr.line(f"  {C['b']}preflight{C['0']}")
    need_pod = n1 > 0 or any(k == "grounded" for p, _n, k in todo if p == 2)
    if not preflight(scr, need_pod, n1, n2, recipe, sky_cache, scratch_label):
        scr.line("")
        scr.line(f"  {C['r']}preflight failed — fix the above and re-run{C['0']}")
        scr.done()
        return 1
    scr.line("")

    if args.dry_run:
        for ph, n, k in todo:
            scr.line(f"    phase {ph}  {n:<36} {k}")
        scr.line("")
        scr.line(f"  {C['y']}dry run — nothing rendered{C['0']}")
        scr.done()
        return 0

    if not todo:
        scr.line(f"  {C['g']}nothing to do — every scene is current{C['0']}")
        scr.done()
        return 0

    # ETA uses the running mean of real per-phase timings, falling back to nominal.
    timings = {1: [], 2: []}
    totals = {"mean": lambda ph: (sum(timings[ph]) / len(timings[ph])) if timings[ph]
              else NOMINAL[ph]}

    t_start = time.time()
    ok = fail = 0
    failed = []
    mb_total = 0.0
    try:
        for i, (ph, name, kind) in enumerate(todo):
            scr.line("")
            scr.line(f"{C['b']}▶ [{i + 1}/{len(todo)}] {name}{C['0']}  "
                     f"{C['dim']}{kind} · phase {ph}{C['0']}")
            good, secs, mb = run_scene(scr, name, ph, args.quality,
                                       (i, len(todo)), totals, t_start, extra_env)
            timings[ph].append(secs)
            state[name] = {"ok": good, "recipe": recipe, "quality": args.quality,
                           "seconds": round(secs, 1), "mb": round(mb, 1),
                           "when": time.strftime("%Y-%m-%d %H:%M:%S")}
            with open(state_path, "w") as f:
                json.dump(state, f, indent=1)
            if good:
                ok += 1
                mb_total += mb
            else:
                fail += 1
                failed.append(name)
    except KeyboardInterrupt:
        scr.line("")
        scr.line(f"  {C['y']}interrupted — state saved. Re-run the same command to "
                 f"resume.{C['0']}")
        scr.done()
        return 130

    scr.done()
    el = time.time() - t_start
    print()
    print(f"{C['b']}══ done ══{C['0']}")
    print(f"  {C['g']}{ok} ok{C['0']}" + (f"   {C['r']}{fail} failed{C['0']}" if fail else ""))
    for n in failed:
        print(f"    {C['r']}·{C['0']} {n}")
    print(f"  wall clock          {hms(el)}")
    print(f"  written             {mb_total / 1000:.2f} GB across {ok} scene(s)")
    print(f"  log                 {logpath}")
    if fail:
        print(f"  retry the failures  python3 scripts/rerender_all.py "
              f"--only <name> --quality {args.quality}")
    print()
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
