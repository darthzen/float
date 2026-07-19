# Float — Session Handoff (for Claude Code)

Purpose: let a Claude Code session resume this project on the Mac and execute the git → entire.io → GitHub-tickets → Ollama-farming setup. Everything needed is in this folder.

## How to resume
1. Sync this `Float/` folder from Dropbox (`/Claude Cowork/Float`) to a real working directory on the Mac. Prefer a normal dev path (e.g. `~/dev/float`), NOT inside the Dropbox-synced folder, so `.git` and entire artifacts don't fight Dropbox sync.
2. Open Claude Code in that directory.
3. Read, in order: this file → `CLAUDE.md` → `starfield_immersive_spec.md` → `BUILD_PLAN.md` → `docs/TICKETS.md`.
4. Follow "Next steps" below. Respect every item under "Hard constraints" — some are Rick's standing rules and must not be skipped.

## Current state (what exists)
- **Spec** — `starfield_immersive_spec.md`: complete feature spec (visionOS 27 dev beta), all decisions and open questions.
- **Build plan** — `BUILD_PLAN.md`: risk-ordered milestones M0–M9 with exit criteria.
- **Scaffold** — `Float/` + `project.yml`: structured Swift stubs keyed to spec sections. **Not compiled** (authored off-Mac); treat as a skeleton to fix against the live SDK.
- **Ticket definitions** — `docs/TICKETS.md` (human-readable) and `scripts/setup_github.sh` (runnable) to create the GitHub milestones/labels/issues.

## What is NOT done yet (the work to resume)
- No local git repo initialized.
- No entire.io configured (`.entire/settings.json` does not exist).
- No GitHub repo or issues created.
- No commits, no pushes.
- Scaffold is uncompiled and unverified.

## Hard constraints (do not violate)
- **Entire gate on commits (Rick's standing rule):** before ANY git commit, verify the repo has `.entire/settings.json`. If it does not, STOP and tell Rick — do not commit. Applies to new repos too.
- **Never claim entire.io is enabled** — you can only verify it, not enable it.
- **This repo syncs to `darthzen` (Rick's own account):** entire artifacts are part of the sync. Leave `.entire/settings.json` and the agent hook files committed, and let the `entire/checkpoints/v1` branch push normally. (The stricter non-darthzen rules do NOT apply here since the owner is darthzen.)
- **Do not push code until entire is set up.** Creating the empty GitHub repo and the issues is fine before then (no code is pushed); the first *commit and push* wait until `.entire/settings.json` is verified.
- **Credentials:** do NOT hardcode Rick's PAT anywhere. Use the Mac's existing `gh` auth (`gh auth status`; `gh auth login` as `darthzen` if needed). The PAT lives in Rick's preferences, not in this repo.
- **Foundational engineering rules** are in `CLAUDE.md` (one clock, deterministic core, camera fixed, safety bubble, comfort gate). Keep them intact.

## Next steps (ordered)
1. **Stage the working dir.** Copy `Float/` to `~/dev/float` (or similar). Confirm `project.yml`, `Float/`, `docs/`, `scripts/` are present.
2. **(Optional) Generate the Xcode project:** `brew install xcodegen` then `xcodegen generate`. Open `Float.xcodeproj`, set Team + bundle id. Not required to set up tickets.
3. **Set up entire.io.** Run Rick's entire enable flow for a darthzen-owned repo (standard config — entire artifacts sync; no `--skip-push-sessions` / no external checkpoint remote needed because owner == darthzen). Then **verify `.entire/settings.json` exists**. If it does not, STOP.
4. **git init + remote.** `git init`; add the GitHub remote once the repo exists (step 5). Do NOT commit yet if `.entire/settings.json` is not present.
5. **Create the GitHub repo + tickets.** Review the config vars at the top of `scripts/setup_github.sh` (owner, repo name, visibility — defaults: `darthzen/float`, private, milestones+labels), then run it. It creates the empty repo, labels, milestones M0–M9, and all issues. It does NOT push code.
6. **First commit + push.** Only after `.entire/settings.json` is verified: `git add -A && git commit` the scaffold, then push. Let the `entire/checkpoints/v1` branch push to darthzen normally.
7. **Wire Ollama farming.** See "Farming to Ollama" below.

## Farming to Ollama
The GitHub issues are the ticket queue. Each ticket is self-contained: Context (spec §), Do, Acceptance, Depends-on.

- **Only farm tickets labeled `agent:ollama-ready`** whose dependencies are closed. These are code/stub-implementation tasks an LLM can do from the spec + scaffold.
- **Never auto-farm `agent:needs-human` tickets.** These require a person in the headset or human judgement: on-device depth/feel sign-off, comfort tests (vection), 90 fps perf gates, and asset-license verification. Route these to Rick.
- Suggested loop: pick the lowest-milestone `agent:ollama-ready` open issue with no open dependencies → hand the issue body + `CLAUDE.md` + relevant `Float/` files to the Ollama agent → open a branch/PR → Rick reviews → close. Keep one milestone flowing before opening the next.
- Milestone order is the dependency order: M0 → M1 → M2 → M3 → M4 → {M5, M6} → M7 → M8 → M9. **M1 (prove depth) is the make-or-break gate** — do not farm later milestones' work ahead of an M1 sign-off.

## Open decisions to settle (carry-over)
- Repo name / visibility / whether to add a GitHub Projects v2 board (defaults chosen in `setup_github.sh`: `float`, private, no board — flip `MAKE_PROJECT=1` to add one).
- Spec §11 open items still unresolved: nebula backend commit (#2), backdrop source (#3), star distribution (#4), TimeScale range (#5), resolution budget (#6), environment variety (#7), hyperspace default intensity (#8), star brightness defaults (#11), ring vantage (#12), comet determinism (#13), reachable-rocks mechanism (#14). Each is called out in the relevant ticket.

## File map
```
Float/
  HANDOFF.md                 ← you are here
  CLAUDE.md                  ← project rules + conventions for Claude Code
  starfield_immersive_spec.md
  BUILD_PLAN.md
  project.yml                ← XcodeGen
  .gitignore
  docs/TICKETS.md            ← human-readable ticket list
  scripts/setup_github.sh    ← creates repo + milestones + labels + issues
  Float/…                    ← Swift scaffold (App, Immersive, Environment, Animation, Layers, Bodies, Interaction, Persistence, Resources)
```

## Verification checklist before farming starts
- [ ] `.entire/settings.json` exists and is verified (never claimed, only checked).
- [ ] GitHub repo `darthzen/float` exists; milestones M0–M9 and all issues created.
- [ ] Initial scaffold committed and pushed; `entire/checkpoints/v1` pushed to darthzen.
- [ ] Labels present: `agent:ollama-ready`, `agent:needs-human`, `risk:*`, `type:*`.
- [ ] Ollama farming loop only consumes `agent:ollama-ready` + unblocked issues.
