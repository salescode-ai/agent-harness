---
name: harness-init
description: Set up, resume or upgrade the agent harness in a repository. Scans first, applies everything the code proves, shows the file tree, then interviews one layer at a time (Guides, Tools, Sensors, Context & State, Observability) and proves the result. Use once per repo, to continue an unfinished setup, to refresh harness scripts after a plugin upgrade, or to bring a v1 harness up to date. Arguments: `[<workspace member>] [one-shot]`; `one-shot` skips the interview.
disable-model-invocation: true
---

# Harness Init

Scan first, ask last. Apply what the code proves; ask only what code can't answer. `${CLAUDE_PLUGIN_ROOT}` is this plugin's folder (two levels above this file). Per-layer detail: `references/layers.md`. File layout and owners: `references/layout.md`.

**While this skill runs, it is the process.** Do not start planning, test-first, review or interview skills from other plugins.

## Ground rules

- **Evidence or a marker.** Every identifier you write (path, env var, target, route, class) needs a `file:line` you observed, else `[verify]` or `TODO`. READMEs are claims, not evidence.
- **Extend, don't clobber.** Read existing files first. Edits to the developer's content are gathered into one diff, approved once.
- **Never** fix legacy errors, loosen a tool's config, `sudo`, fetch secrets or write `.env` during init.
- **Ratchet.** A rule traces to a real failure, incident or hard constraint. No generic advice.

## 0. Where, resume or upgrade

- **Workspace member.** If `harness-workspace.json` is here and this folder is not a git repo: with a first argument naming a member (its `name` or `path` there, or a path to a repo), work **inside that member** — every path and command below is relative to it, and nothing outside it is touched. Without one, stop: list the members (name · path · harness state) and say "run `/agent-harness:harness-init <member>`" (one-shot: `/agent-harness:harness-init <member> one-shot`).
- **Existing harness → upgrade.** On every re-run where the harness exists (all in-scope layers done, or a v1 harness), hand over to **harness-upgrade**: follow `${CLAUDE_PLUGIN_ROOT}/skills/harness-upgrade/SKILL.md` (or tell the developer to run `/agent-harness:harness-upgrade`). It runs `assets.py" status .` and `assets.py refresh .` (unmodified plugin copies only; `modified` ones are reported as "modified locally, review diff" with the printed command), then the versioned migrations. Resuming an unfinished setup: run its steps 1–2 first, then continue below.
- Read `.harness/init-state.json` if present: `{"layers_done":[…], "answers":{…}, "gate_wired":bool, "target":"Robust"}`. Layer keys: `guides`, `tools`, `sensors`, `context`, `observability`. Say "Resuming at <next layer>" and jump to step 4 for the first layer **in scope for `target`** (Functional: `guides`, `sensors`; Robust/Enterprise: all five) that is not in `layers_done`; never re-ask a recorded answer. If `.harness/scan.json` is missing, its `head` differs from `git rev-parse HEAD`, or any `commands[]` entry lacks `baseline`, redo step 1 (scan and baselines) first.
- **v1 harness** (`AGENTS.md`/`INVARIANTS.md` exist, no state file) that harness-upgrade cannot bring up to date: same flow, but the tree in step 3 lists only differences and questions already answered by existing files are skipped.

## 1. Scan (no questions)

0. Run the probe in `references/probe.md` (fresh repo only); keep the answer in the conversation for step 5.
1. `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/scan.py" . --write` → `.harness/scan.json` (gitignored, keyed to `head`). If it exists with the current `git rev-parse HEAD`, reuse it.
2. Dispatch `repo-cartographer` (`agent-harness:repo-cartographer`; no subagents → follow `${CLAUDE_PLUGIN_ROOT}/agents/repo-cartographer.md` yourself). Keep its report in the conversation.
3. **Green baseline.** After the cartographer returns (it re-runs the scan), run every `commands[]` entry except `install`, `dev` and watch modes from its `module` folder on the untouched repo (timeout 5 min each). Run non-interactively: Jest / react-scripts with `CI=true` (otherwise they watch), Maven with `-B -q`, Gradle with `--console=plain`. Add `"baseline": "pass"` · `"fail: <n> errors"` · `"skipped: <why>"` and `"baseline_secs": <wall-clock seconds>` to that entry in `scan.json`. A failure caused by the environment (no Docker, no JDK) is `skipped`, not `fail`. A timeout is `"skipped:timeout"`: not wired, and reported under Still open.

## 2. Decide auto vs ask

**Applied automatically (evidence-backed):** commands that pass the green-baseline run; an existing compose file, seeds and git-hook manager; paths found, the dependency inventory and skeleton files; `.gitignore` entries; moving pasted pack guidance into `AGENTS.md` (a move, not a rewrite); catalog sensors that match evidence and pass their proof.

**Always asked:** target level; Agent Authorization; new invariants and their severity; footguns and incidents; glossary definitions; adding a dependency or tool; CI opt-in; `.claude/settings.json` permissions; generating a compose file or seeds; where to read unresolved dependencies; isolated or shared worktree services; stub, shared-environment or none for external services.

A tool whose baseline is `fail` is wired in changed-files mode (`references/layout.md`) and recorded as an invariant `… — Enforced by: not yet enforced (<n> errors, <date>)`.

## 3. Show the layout tree, then write

Show one tree. Mark every file `auto-filled ✓` · `skeleton + TODO` · `needs your answer ?` · `~ extend` · `→ move`, and tag its layer:

```text
AGENTS.md                 skeleton + TODO     [guides]   Verification ✓ from scan, Authorization ?
INVARIANTS.md             needs your answer ? [guides]   severity per rule
CLAUDE.md                 → move              [guides]   18 pasted lines → AGENTS.md Working Principles
Makefile                  ~ extend            [tools]    include harness.mk (keeps your help, build)
scripts/harness/          auto-filled ✓       [tools]    cmd.sh, lint.sh, setup.sh, sensors/
.githooks/                auto-filled ✓       [sensors]  pre-commit → check-fast, pre-push → check
docs/SETUP.md             skeleton + TODO     [tools]    3 unresolved dependencies ?
```

After **one** yes, **first** save `.harness/init-state.json` with `"gate_wired": false` (keep any keys already there; one-shot too): until step 5 sets it `true`, the stop gate and the git hooks stay silent. Then write everything. **Install step** (copy, then `chmod +x` the scripts):
- `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/assets.py" install .` copies the plugin-owned scripts — `scripts/harness/` (cmd.sh, lint.sh, related-tests.sh, setup.sh, setup-proof.sh, sensor-proof.sh, local-guard.sh, sensors/), `.githooks/`, `harness.mk` — and records their sha256 in `scripts/harness/assets.json` (commit it; later upgrades refresh from it). Sensor `registry.json` and fixtures are copied only if absent and stay repo-owned.
- `assets/docs/agents/issue-tracker-<tracker>.md` → `docs/agents/issue-tracker.md`, plus `triage-labels.md`, `domain.md` (layers.md → Guides)
- `.githooks/`: Do **not** set `core.hooksPath` here: with `hook_manager: none` it is set by `make setup` once Sensors answers "git hooks: on"; with a manager, its config calls these scripts (layers.md → Sensors)
- `harness.mk` (repo root): add `include harness.mk` to the `Makefile` **after** the repo's own default target (create a `Makefile` with only the include if none exists). For each target the Makefile already defines (`help`, `check`, `test`, `setup`…), put `HARNESS_DEFINE_<NAME>=0` above the include (upper-case, `-` → `_`) and ask which one wins. Set `HARNESS_*` variables to commands whose baseline is `pass`; a tool whose baseline is `fail` is wired in its changed-files form (`references/layout.md`, `harness_changed`) and its debt recorded as a `not yet enforced (<n> errors, <date>)` invariant, so `check` can pass on today's code. A `skipped` tool is wired like a declined one, never left on the failing default: `HARNESS_LINT = @echo "lint: skipped (<why>, <date>)"` plus a `not yet enforced (skipped: <why>, <date>)` invariant, so `check` passes on what is runnable and the gate can wire. Wire the same non-interactive form the baseline used (`CI=true` for Jest/react-scripts, `-B` for Maven, `--console=plain` for Gradle) into `HARNESS_TEST_ALL`/`_ONE`/`_CHANGED`. A tool the repo does not have (no linter, no type checker) is **declined**, not left failing: `HARNESS_LINT = @echo "lint: none (declined <date>)"` plus an invariant `… — Enforced by: not yet enforced (declined <date>)` (`references/layout.md`). `HARNESS_SEED`/`RESET`/`DEV` go **above** the include (their targets exist only when set). Then `make -n help` must succeed.
- **check-fast runs tests.** Full-suite baseline `pass` in ≤ 60 s → `HARNESS_TEST_SECS = <baseline_secs>` (check-fast runs the whole suite). Otherwise `HARNESS_TEST_CHANGED = bash scripts/harness/related-tests.sh [-C <module>] <stack> "<runner>"` (jest · vitest · node · maven · gradle · go · pytest; `references/layout.md`), so a changed **source** file runs its tests. Never leave both empty while the repo has tests.
- **Base branch.** `b="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"`; if empty, use `origin/main` if `git rev-parse -q --verify origin/main` succeeds, else `origin/master`, else the current branch's upstream (`git rev-parse --abbrev-ref @{u}`). Write `HARNESS_BASE = <that ref>` (e.g. `origin/master`) into the `Makefile` above the include, and list it under Assumed.
- Templates from `assets/` (AGENTS.md, INVARIANTS.md, CLAUDE.md, GLOSSARY.md, docs/); append `assets/gitignore.append` to `.gitignore`. Keep AGENTS.md Verification in its short form, never a list of every target; another runner: its equivalents and its help command, recorded as `"help"` in `.agents/harness.json`.

New files carry `TODO` where an answer is pending. TODOs are lint **warnings** during setup.

## 4. Interview: one section per layer

Order: **Guides → Tools → Sensors → Context & State → Observability**. A `Functional` target covers Guides and Sensors only; `Robust` all five; `Enterprise` all five plus CI, CODEOWNERS and audit history. Questions per layer: `references/layers.md`.

Every section has exactly this shape. Show one section, wait for the answer, apply it, then move on:

```text
## Sensors — checks that catch mistakes before a human does
Found:    eslint passes (package.json:12) · pytest fails on main (56 errors) · husky present
Will do:  pre-commit runs check-fast via husky · pytest wired in changed-files mode
1. Severity of "no prod data in seeds"?   a) Critical ➡️  b) Important  c) Nice-to-have
2. Wire the "controllers bypass service" sensor (ArchUnit)?   a) yes, prove it first ➡️  b) skip
3. Add a CI workflow?   a) no, git hooks are enough ➡️  b) yes (shown below why)
Reply with numbers and letters ("1a 3b"), or "defaults" to accept every ➡️.
Assumed — change any time: hook names · check-fast base origin/main · fixture folder
```

- At most 5 numbered questions, each with 2–4 options and one `➡️` default. Never ask what the scan answered.
- Low-stakes items (naming, cadence, limits) are not asked; list them under `Assumed — change any time`.
- After each section: write its files, append the layer key to `layers_done`, store answers under `answers.<layer>`, save `.harness/init-state.json`. Target goes to `"target"` and to `INVARIANTS.md` as `Harness target: <level>`.

## 5. Verify

1. `bash scripts/harness/lint.sh` — FAILs fixed, TODO warnings listed.
2. Check gate: `c="$(bash scripts/harness/cmd.sh . check-fast)" || { echo "check-fast not wired (exit $?)"; exit 1; }; eval "$c"`; then the same with `check`. An unresolved target (exit 3/4, empty output) is **not** green. Set `"gate_wired": true` only when check-fast resolved **and** exited 0; otherwise save `"gate_reason": "<one line: what failed>"` and list it under Still open (the session hook shows it until the gate is wired). Then prove the gate can fail: `bash scripts/harness/gate-proof.sh` plants one failing test in a scratch worktree; `make test T=<it>`, `make test T=<no such test>` and check-fast must each exit non-zero. It records `"gate_red_proven"` (and `"gate_red_reason"`) in `.harness/init-state.json`. `NOT proven` means a test command swallows its exit code (`; :`) or passes on 0 tests: fix the wiring (layout.md, **Test commands keep their exit code**) and rerun; list a remaining failure under Still open.
3. Setup proof (only when `tools` is in scope for the target; otherwise skip and say so): `setup-smith` runs `bash scripts/harness/setup-proof.sh` in a fresh clone (commit the wiring first, or tell the developer the proof sees only committed files).
4. Sensors: `bash scripts/harness/sensor-proof.sh --recheck`.
5. Probe again (fresh session if possible); report the difference in the conversation only.

## 6. Final report

Run `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/level.py" . --json --run-checks --log` (runs the real check, so the reported and the logged level agree; the log line seeds the audit history) and report from its output:

```text
Level: <measured> · target: <target> · blocked by: <first blockers>
Applied automatically: <n> — <one line each>
Assumed — change any time: <list>
Still open: <TODOs with file:line> · <invariants "not yet enforced">
Next: make setup (you run it: git config + services; hooks pending until then) · /harness-audit in a month · /harness-garden weekly
Run /agent-harness:harness-improve to strengthen <top 3 gaps: blockers, then TODO-heavy files, then not-yet-enforced invariants>?
```

Interactive session: end by asking whether to start harness-improve now (yes → follow `${CLAUDE_PLUGIN_ROOT}/skills/harness-improve/SKILL.md`).

## one-shot mode

Same flow without step 4: every ➡️ default is taken, nothing is asked, and every new file starts with `<!-- generated in one pass: verify before trusting -->`. Always-asked items with no safe default (Authorization, incidents, glossary meanings, CI, settings.json, new dependencies, compose file or seed generation) are never applied by default: they are left as `TODO` and listed under Still open. Save `init-state.json` with all layer keys and `"answers": {"mode": "one-shot"}`. One-shot **never runs `make setup`** (it changes git config and starts services) nor sets `core.hooksPath`: Still open says `git hooks: pending make setup`, and `make setup` is the first Next step.
