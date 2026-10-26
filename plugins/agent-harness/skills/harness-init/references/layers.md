# The five layers: what each interview section covers

One section per layer, in this order. Each section of the interview uses the shape in `SKILL.md` step 4: one-line explanation → `Found:` → `Will do:` → ≤5 numbered questions with a `➡️` default → `Assumed — change any time`. Ask only the questions whose answer the scan could not give. `"defaults"` accepts every `➡️` in the section.

Scope by target level: `Functional` → Guides and Sensors; `Robust` → all five; `Enterprise` → all five plus CI, CODEOWNERS and audit history.

## Guides (`guides`)

**What it is.** The instructions an agent reads before acting: the map (`AGENTS.md`), the hard rules (`INVARIANTS.md`), vocabulary and decisions. Guides steer before the work starts; sensors catch what slipped through.

**scan.json keys.** `harness_files`, `pasted_guidance`, `pack_folders`, `modules`, `risk_paths`, `stacks`.

**Applied automatically.**
- `AGENTS.md` skeleton with Verification filled from commands whose baseline is `pass`, Module map from `modules`, Working Principles from the template.
- `CLAUDE.md` becomes the shim (`@AGENTS.md`, `@INVARIANTS.md`). Lines listed in `pasted_guidance` **move** into `AGENTS.md → Working Principles`; a line that repeats an existing principle is dropped, not duplicated. Move by script, then check every original line exists somewhere. An `@import` in the old file moves to the module shim of the folder it governs.
- `INVARIANTS.md` with the Harness Integrity block verbatim, and `Harness target: <level>`.
- Module `AGENTS.md` (+ a `CLAUDE.md` containing `@AGENTS.md`) only for `risk_paths` modules or a module with its own toolchain.
- `## Agent skills` block and Work Artifacts in `AGENTS.md` (rules: `references/plugins.md`).
- `docs/agents/`: detect the tracker from `git remote` (github.com → github, gitlab → gitlab); otherwise ask (jira, local). Copy `assets/docs/agents/issue-tracker-<tracker>.md` → `docs/agents/issue-tracker.md` (ship only that variant), plus `triage-labels.md` and `domain.md`. Fill the tracker key or labels from the answer; never leave the AGENTS.md pointers dangling.

**Questions (defaults).**
1. Target level? a) Functional b) Robust ➡️ c) Enterprise. Recommend from the scan: no tests or a failing baseline → Functional; CI plus CODEOWNERS already present → Enterprise; else Robust.
2. Agent Authorization — "May without asking": a) edit, test, commit on a feature branch ➡️ b) edit and test only. "Must stop and ask": a) migrations, auth, payments, public API, deleting data, pushing to main ➡️ b) add your own.
3. Footguns: "What has broken in production or surprised a new joiner?" Offer the cartographer's `fix`/`revert` hotspots as prompts. a) list them now b) none yet ➡️ (Footguns stays `TODO`).
4. Seed 5–10 glossary terms? a) yes, I'll define them b) later ➡️ (header only). Definitions come from the developer, never from code.

**Assumed — change any time.** Section names, the generic Working Principles, module map wording.

**Writes.** `AGENTS.md`, `INVARIANTS.md`, `CLAUDE.md`, module `AGENTS.md`/`CLAUDE.md`, `GLOSSARY.md`, `docs/ARCHITECTURE.md`, `docs/DECISIONS.md`, `docs/adr/`, `docs/agents/`.

## Tools (`tools`)

**What it is.** Tool & Permission Boundaries: the commands an agent may run, how a fresh machine gets to a working dev setup, and what the agent may not touch.

**scan.json keys.** `commands` (with `baseline`), `versions`, `services`, `env_vars` (`resolved` true/false), `migrations`, `seeds`, `is_worktree`.

**Applied automatically.**
- `harness.mk` included, `HARNESS_*` set to commands whose baseline is `pass`; failing tools in changed-files mode.
- An existing compose file, migrations and seeds wired into `make setup`.
- `docs/SETUP.md` with the dependency inventory: every resolved item with its `file:line`, every unresolved item as `TODO`.

**Dispatch `setup-smith`** (`agent-harness:setup-smith`) with `scan.json` and this section's answers. It wires `setup-deps`, `setup-services`, `setup-migrate`, `seed`, `smoke`, proposes `compose.harness.yml` or a synthetic seed only after a yes, and runs `bash scripts/harness/setup-proof.sh`.

**Questions (defaults).**
1. Runner? a) `make` ➡️ b) register another (`.agents/harness.json` with `runner` and `commands`; `harness-lint` then checks `AGENTS.md` agrees).
2. Local services across worktrees: a) isolated per worktree (own compose project, free ports, own DB) ➡️ b) shared.
3. Only when services are needed and there is no compose file — generate a local-only `compose.harness.yml` (versions from config)? a) show it first, decide then ➡️ b) no, I run them myself. Never written without an explicit yes; "defaults" and one-shot do not count as one.
4. Each external service that can't run locally: a) stub from OpenAPI or recorded responses ➡️ when a contract exists b) shared dev environment URL c) not needed (noted unavailable).
5. Permission rules for `.claude/settings.json`: a) apply ➡️ b) show only. Proposed rules:
   - deny `Read(./.env)`, `Read(./**/.env)`, `Read(./**/.env.local)`, `Read(./**/.env.*.local)`, `Read(./**/.env.prod*)`, `Read(./**/.env.staging*)` (not `.env.*`: `.env.example`/`.env.sample` must stay readable), `Read(./**/secrets/**)`, `Read(./**/*.pem)`, `Read(./**/*.key)`;
   - deny the dangerous infrastructure and production commands found in the repo (e.g. `Bash(terraform apply:*)`, `Bash(kubectl delete:*)`, a deploy script), each with its `file:line`;
   - allow the runner's commands, e.g. `Bash(make check:*)`, `Bash(make test:*)`.
   Start from `assets/claude-settings.json`. Claude Code may refuse the write: then show the full JSON for the developer to add, and do not work around the refusal.

**Then, one at a time, for each unresolved dependency** (`env_vars` with `resolved: false`, services with no config): "Where can I read the details for X?" a) wiki URL b) another repo c) a teammate d) not needed locally. Record each answer in `docs/SETUP.md`. `setup-smith` asks separately, with an explicit yes, about a synthetic seed when the repo has none.

**Assumed — change any time.** Port range, compose project naming, `.env.local` as the worktree file.

**Writes.** `Makefile` include, `harness.mk`, `scripts/harness/*`, `.agents/harness.json` (other runner only), `docs/SETUP.md`, `.claude/settings.json`, `compose.harness.yml` and seed files (only after a yes).

## Sensors (`sensors`)

**What it is.** Checks that observe the work and fail loudly: the `check`/`check-fast` gate, project sensors for invariants, and where those checks run.

**scan.json keys.** `commands` (`lint`, `typecheck`, `test` with `baseline`), `stacks`, `risk_paths`, `seeds`, `hook_manager`, `ci`.

**Applied automatically.**
- `check` = lint + typecheck + tests + harness-lint; `check-fast` = changed files, under 60 s.
- Critical invariant, always: `- No real customer or production data in seeds or fixtures — Severity: Critical — Enforced by: scripts/harness/sensors/no-prod-data.sh`, kept only if its proof passes, else `not yet enforced`.
- Git hooks: pre-commit runs `check-fast`, pre-push runs `check`.
  - `hook_manager: none` → `.githooks/` from `assets/githooks/`. Only after question 4 is answered "on": `make setup` sets `core.hooksPath .githooks` (ask the developer to run it, or `git config core.hooksPath .githooks`, so this checkout is covered; the agent's guard blocks that command). Never at install time.
  - With a hook manager, still copy `assets/githooks/*` to `.githooks/` (do **not** set `core.hooksPath`) and have the manager call them; they resolve the target and skip quietly when it is not wired:
  - `husky` → append `bash .githooks/pre-commit  # harness check-fast` to `.husky/pre-commit` and `bash .githooks/pre-push  # harness check` to `.husky/pre-push`.
  - `lefthook` → in `lefthook.yml`: `pre-commit: commands: harness-check-fast: run: bash .githooks/pre-commit`, and `pre-push: commands: harness-check: run: bash .githooks/pre-push`.
  - `pre-commit` → a `repo: local` hook in `.pre-commit-config.yaml`: `id: harness-check-fast`, `entry: bash .githooks/pre-commit`, `language: system`, `pass_filenames: false`; and `id: harness-check`, `entry: bash .githooks/pre-push`, `stages: [pre-push]`.

**Questions (defaults).**
1. Proposed invariants, each with severity: a) Critical (fails `check`, blocks the stop gate) b) Important ➡️ (warning; `harness-verify` sends it to a human) c) Nice-to-have (audit only). Format: `- <rule> — Severity: <tier> — Enforced by: <target | hook | sensor | human review | not yet enforced>`.
2. Candidate sensors from `references/sensor-catalog.md` that match evidence: a) build and prove ➡️ b) skip. For each accepted one, dispatch `sensor-smith` (`agent-harness:sensor-smith`) with the invariant line and `scan.json`; wire it into `check` only after `sensor-proof.sh <name>` passes.
3. A tool is missing for a sensor: a) add it as a dev dependency (named, with the install line) b) use a plain test or script ➡️.
   The repo has no linter or type checker at all: a) declined ➡️ — `HARNESS_LINT = @echo "lint: none (declined <date>)"` plus a `not yet enforced (declined <date>)` invariant (`layout.md`) b) add one now (as a dependency).
4. Git hooks: a) on ➡️ b) off (the session hook will warn).
5. CI workflow? Show the "Where checks run" table below first. a) no, hooks are enough ➡️ b) yes: copy `assets/harness.yml` to `.github/workflows/` or translate it to the repo's CI. Enterprise requires b.

Where checks run (show before question 5):

| Place | Default | Notes |
|---|---|---|
| Agent hooks (stop gate, guards) | on | Agents only; Claude Code |
| Git hooks: pre-commit runs `check-fast`, pre-push runs `check` | on | If a hook manager exists (husky, lefthook, pre-commit), add to its config. Otherwise use `.githooks/` with `core.hooksPath`, set by `make setup`. The session hook warns when the hooks are off. |
| CI workflow | opt-in | Generated only on a yes, after the explanation is shown. It is the only check nobody can skip; required for Enterprise. |

**Assumed — change any time.** Fixture folder, `HARNESS_BASE` (derived: `origin/HEAD`, else `origin/main`, else `origin/master`), sensor names.

**Writes.** `INVARIANTS.md` rules, `harness.mk` variables, `scripts/harness/sensors/` (registry, sensors, fixtures), hook config, CI workflow (only after a yes).

## Context & State (`context`)

**What it is.** What an agent loads for a task, and where work in progress lives so it survives a context reset.

**scan.json keys.** `pack_folders`, `harness_files`, `modules`.

**Applied automatically.**
- `docs/plans/` (`active/`, `done/`, `TEMPLATE.md`); unverified claims in plans are marked `[verify]`.
- `.gitignore` entries for pack scratch folders in `pack_folders`, plus `.harness/` and `.worktrees/`.
- Existing pack folders in use are kept; Work Artifacts points at them instead of moving history.

**Questions (defaults).**
1. Context loading table (task type → files to read): a) the proposed rows from modules and docs ➡️ b) edit them.
2. Plan and spec paths: a) `docs/plans/`, `docs/specs/` ➡️ b) keep the existing folders found.
3. Where packs keep working notes: a) `.scratch/` (gitignored) ➡️ b) another folder.

**Assumed — change any time.** Plan template sections, worktree folder `.worktrees/`.

**Writes.** `AGENTS.md` Context loading and Work Artifacts, `docs/plans/`, `.gitignore`.

## Observability (`observability`)

**What it is.** Observability & Lifecycle: keeping the harness itself healthy over time: limits, cadence and the audit history.

**scan.json keys.** `harness_files`, `ci`.

**Applied automatically.**
- `## Cadence` in `AGENTS.md`: quick audit monthly, full audit quarterly or after any incident, garden weekly.
- Default limits (root `AGENTS.md` ≤ 100 lines, auto-loaded ≤ 3k tokens warn / 5k fail).
- First history row: written by the final report's `level.py . --json --run-checks --log` (`SKILL.md` step 6) → `docs/harness/AUDIT-LOG.md`.

**Questions.** None by default. Cadence and budget overrides are assumed; ask only if the developer raises them (overrides go in `INVARIANTS.md` `## Context Budget` / `## File Size Budget`). Enterprise target with CI present: a) add a CI audit job b) no ➡️.

**Assumed — change any time.** Cadence, budgets, log location.

**Writes.** `AGENTS.md` Cadence, `docs/harness/AUDIT-LOG.md`.
