# agent-harness 2.0.0 — Design Spec

Date: 2026-10-26 · Status: approved design (grilling session, 55 decisions) · Basis: [Adobe AI Repo Harness Guide v1.1.0](https://opensource.adobe.com/ai-repo-harness-guide/)

## 1. Goal

A Claude Code plugin that **sets up, reviews and audits** an engineering-time harness for any repository, or for a multi-repo working folder. It must work alongside any third-party skill pack without naming one. The harness holds the facts and rules; packs bring process.

Out of scope, as in Adobe: runtime harness concerns, such as tool dispatch, retries, cost ceilings and runtime metrics.

## 2. Principles

- **Evolve v1** rather than rewrite it. Keep the hooks, reviewer agents, lint, workspace script and ownership model.
- **Five layers organise everything.** The layers are Guides · Sensors · Context & State · Tool & Permission Boundaries · Observability & Lifecycle. Every scan finding, generated file, audit item and interview section is tagged with its layer.
- **Evidence or a marker.** Facts come from the scan, with a `file:line` source. A fact the scan can't find is marked `[verify]` or `TODO`, never invented.
- **Ask only what code can't answer.** Apply automatically whatever the scan proved. Ask about judgement calls, with a default offered.
- **No named packs.** The plugin's text never names a third-party plugin. Compatibility comes from providing generic conventions.
- **Ratchet.** A rule earns its place by tracing to a real failure, incident or hard constraint.
- **A model grading itself is not a measurement.** Persist script-measured numbers only.

## 3. Components

| Kind | Name | Status |
|---|---|---|
| Skill (user-invoked) | `harness-init` | rewritten flow (§4) |
| Skill (user-invoked) | `harness-audit` | **new**, read-only (§7) |
| Skill (user-invoked) | `harness-workspace` | revised (§9) |
| Skill | `harness-verify`, `harness-session`, `harness-learn`, `harness-garden`, `harness-glossary` | kept; garden applies audit fixes; session drops the named-pack reference |
| Agent | `repo-cartographer`, `verifier`, `invariants-reviewer`, `scope-guard`, `cross-repo-reviewer`, `harness-auditor` | kept; cartographer writes `scan.json`; auditor reports layers and level |
| Agent | `sensor-smith` | **new** (§6) |
| Agent | `setup-smith` | **new**: builds and proves `make setup` (§5.3) |
| Hooks | session-context, guard-bash, guard-files, stop-gate | extended (§8) |
| Self-test | `tests/run.sh` + fixture repos | **new** (§11) |

## 4. `harness-init` flow

1. **Full scan, no questions.**
   - `scan.sh` plus the `repo-cartographer` agent write `.harness/scan.json`. It is gitignored and keyed to `HEAD`, and `audit`, `garden` and a resumed setup reuse it.
   - Contents: stack and modules, candidate commands with their green-baseline results, the dependency inventory (§5.2), high-risk areas, pack residue (folders, guidance pasted into `CLAUDE.md`), an existing git-hook manager, CI presence, and the harness files already present.
2. **Work out what can be applied automatically** from the scan: everything backed by evidence (see the auto/ask split below).
3. **Show the layout tree.**
   - Every file is marked `auto-filled ✓` · `skeleton + TODO` · `needs your answer ?` · `~ extend` · `→ move`, and tagged with its layer.
   - After one confirmation, write all the files.
   - Edits to a developer's existing content are gathered into a single diff, approved once.
4. **One section per layer**, in this order: Guides → Tool & Permission Boundaries → Sensors → Context & State → Observability & Lifecycle.
   - Each section starts with a one-line explanation of the layer, then **"Here's what we found → here's what we'll do"**, then up to about 5 numbered questions. Each question offers 2–4 options with a recommended default.
   - Answering "defaults" accepts the whole section.
   - Low-stakes items (naming, cadence, limits) are not asked. They are applied and listed under **Assumed — change any time**.
5. **Verify**: `harness-lint`, `make check`, the fresh-clone setup proof (§5.3), and sensor proofs (§6).
6. **Final report**: current level and target level, what was applied automatically, the assumed items, and what is still open (TODOs, unenforced rules).

Behaviour that applies to the whole flow:
- **Resume.** Progress is saved in `.harness/init-state.json` (layers done, answers given). A later run continues at the next layer.
- **Upgrading a v1 repo.** The tree shows only the differences, and answers already recorded are not asked again.
- **`one-shot` mode.** Same flow, but without step 4: every default is used and new files are stamped `generated in one pass: verify before trusting`.
- **During setup.** `TODO` markers are lint **warnings**. The stop gate stays silent until `check-fast` is wired up. The audit counts TODOs as gaps.

**Applied automatically (evidence-backed):**
- commands that pass the green-baseline run;
- an existing compose file, seeds and git-hook manager;
- paths found, the dependency inventory and skeleton files;
- `.gitignore` entries;
- moving pasted pack guidance into `AGENTS.md` (a move, not a rewrite);
- catalog sensors that match evidence and pass their proof.

**Always asked:**
- target level;
- Agent Authorization;
- new invariants and their severity;
- footguns and incidents;
- glossary definitions;
- adding a dependency or tool;
- CI opt-in;
- `.claude/settings.json` permissions;
- generating a compose file or seeds;
- where to read unresolved dependencies;
- isolated or shared worktree services;
- stub, shared-environment or none for external services.

### Questions per layer (examples)

- **Guides:**
  - target level (§7.2, recommended from the scan);
  - "May without asking / Must stop and ask";
  - footguns from incidents;
  - 5–10 seed glossary terms (optional).
- **Tools:**
  - runner (`make`, or register another);
  - unresolved dependencies ("where can I read X?");
  - Docker generation;
  - worktree isolation;
  - external services;
  - permission rules.
- **Sensors:**
  - proposed invariants with severity;
  - candidate sensors from the catalog;
  - a tool to add when one is missing;
  - git hooks;
  - CI opt-in, with the explanation from §8.3 shown first.
- **Context & State:** context-loading table entries; plan and spec paths; folders for packs' working notes.
- **Observability:** cadence (assumed by default); budget overrides (assumed by default).

## 5. Tool & Permission layer

### 5.1 Command surface

- **Default runner: `make`.** `harness.mk` is included from the root `Makefile`; an existing `Makefile` is extended, never replaced. A target name that already exists goes to the developer to resolve.
- Targets:

  | Target | Does |
  |---|---|
  | `check` | lint + typecheck + all tests + harness-lint |
  | `check-fast` | changed files only, under 60 s |
  | `test [T=]` | all tests, or one file/test |
  | `smoke` | start the app and hit one real path |
  | `setup` | §5.3 |
  | `seed` | reload test data |
  | `reset` | wipe and re-seed local data |
  | `dev` | run the app |
  | `harness-lint` | structural checks on the harness |
  | `help` | list targets |

- `harness.mk` follows Adobe's form: the agent header line, `.DEFAULT_GOAL := help`, `##` help comments.
- **Wiring rules:**
  - Each command is wired only after it passes the green baseline on the untouched repo.
  - A tool that already fails is wired in changed-files mode, and its debt is recorded as an invariant marked `not yet enforced (<n> errors, <date>)`.
  - A missing tool gets a stack-appropriate suggestion and needs the developer's yes. There are no stubs that pretend to pass.
  - Never fix legacy errors or loosen a tool's config during init.
- **Registering another runner.** A team without `make` registers commands in `.agents/harness.json`:
  ```json
  { "runner": "just",
    "commands": { "check": "just check", "check-fast": "just quick", "test": "just test {T}",
                  "setup": "just bootstrap", "seed": "just seed", "reset": "just reset",
                  "smoke": "just smoke", "dev": "just dev" } }
  ```
  - Hooks, the verifier, the workspace gate, the audit and git hooks resolve commands through a shared `harness_cmd <target>` helper. It reads `.agents/harness.json` first and falls back to `make <target>`.
  - `AGENTS.md → Verification` shows the same commands for people, and `harness-lint` fails when the two disagree.
- **`make` missing at runtime.** Hooks warn and skip; they never block.

### 5.2 Dependency inventory

The scan collects these from evidence:
- tool versions: `.nvmrc`, `.tool-versions`, `.sdkmanrc`, `engines`, `toolchain`;
- package manifests;
- `docker-compose*` and `Dockerfile`s;
- connection settings in config (`application.yml`, `settings.py`, `.env.example`), e.g. `DB_HOST`, `KAFKA_BROKERS`, `REDIS_URL`;
- CI install steps;
- migration folders and seed scripts.

Every item is classed as **resolved** (with a `file:line` source) or **unresolved**. Each unresolved item becomes a Tools-layer question: "Where can I read the details for X?", answered with a wiki URL, another repo, a teammate, or "not needed locally". The results go into `docs/SETUP.md`, which owns this information.

### 5.3 `make setup`

**What it does.** Safe to re-run, works on a fresh machine or in any worktree:
1. **Check prerequisites.** Report exactly what is missing.
2. **Install runtimes** only through the repo's own version manager (nvm, sdkman, asdf/mise, pyenv). Never `sudo`, never system-wide installs. For anything else missing, print the exact install command for the OS and stop.
3. **Check registry sign-in** for private package and container registries. If not signed in, say exactly which login is needed and stop. Never store credentials.
4. **Install dependencies.**
5. **Create `.env`** from `.env.example` if missing, plus a gitignored `.env.local` with the worktree-specific values. List the variables that still need a real value. Never fetch secrets.
6. **Start services:**
   - Reuse the repo's compose file. If there is none, `setup-smith` proposes a local-only `compose.harness.yml`, with versions taken from config or confirmed by the developer, written only after a yes.
   - **Each worktree is isolated by default:** its own compose project name (from the worktree folder), free ports picked automatically and written to `.env.local`, and its own database name. Shared services are available as an option in the interview.
   - **External services that can't run locally**, chosen per service: (a) a stub generated from OpenAPI or recorded responses (WireMock or Prism, the default when a contract exists), (b) a shared dev environment URL, (c) not needed (noted as unavailable).
7. **Run migrations.**
8. **Seed** (§5.4).
9. **Enable git hooks** (§8.2).
10. **Smoke.** `make smoke`.

**The final report** is short, and the exit code is non-zero if a required step failed:
```
setup: OK  (fresh clone · worktree feat-x · ports api=8123 db=55432)
services: postgres ✓ redis ✓ orders-api (stub) ✓
data: seeded 42 rows · smoke ✓
needs you: STRIPE_KEY (dev env), docker login ghcr.io
```

**Proof.** During init, `setup-smith` runs `make setup` in a **fresh clone in a temp folder**, so the result can't depend on the developer's checkout. `harness-audit full` repeats this run.

`seed` and `reset` refuse to run against any target that isn't local.

### 5.4 Test data

- Use the existing seeds, fixtures or factories.
- If none exist, the developer can opt in to `setup-smith` writing a small **synthetic** seed from the schema or models: a few rows per main entity, edge cases included. It is proven by loading it and passing `smoke`.
- Critical invariant, always added: **"No real customer or production data in seeds or fixtures."** A sensor flags production database hosts, real-looking emails and phone numbers, and dump files.

### 5.5 Permissions

- The scan proposes `.claude/settings.json` permission rules: deny reading `.env*` and secrets folders, deny dangerous infrastructure and production commands found in the repo, allow the registered runner's commands.
- The developer approves the rules. If Claude Code refuses the write, the content is shown for the developer to add themselves.
- These rules add to the guard hooks.

## 6. Sensors layer

- **Invariants** carry a severity (Adobe's tiers):
  - **Critical**: fails `check` and blocks the stop gate.
  - **Important**: a warning, which `harness-verify` flags for a human.
  - **Nice-to-have**: appears in the audit only.

  Format: `<rule> — Severity: <tier> — Enforced by: <target | hook | sensor | human review | not yet enforced>`.
- **Sensor catalog** (`skills/harness-init/references/sensor-catalog.md`): candidate sensors for each stack. Examples: Spring controllers that bypass the service layer and missing `@Transactional` on writes; React/TS with no direct `fetch` outside an API module; Python import-layer rules; Flyway/Liquibase migration naming; an OpenAPI spec that matches the routes; the "no production data in seeds" check. The scan picks only candidates backed by evidence, and the interview asks about each one.
- **Tool preference:**
  1. a rule in the repo's existing linter;
  2. an architecture-test library already in use or one that fits the stack;
  3. a plain test in the repo's suite;
  4. a script in `scripts/harness/sensors/`.

  A missing tool gets a stack-appropriate suggestion; a new dev dependency needs a yes.
- **`sensor-smith` proof run** (required before a sensor is wired in):
  1. Run on the current code: it passes.
  2. Plant a violation in a **fixture file only**: it fails with a clear, actionable message.
  3. Remove the violation: it passes again.

  The planted violation is kept as a regression fixture under `scripts/harness/sensors/fixtures/`, and `harness-lint` re-runs it to confirm the sensor still fires. The agent works in the current checkout and commits nothing.
- **Where checks run** (§8).

## 7. Audit and maturity

### 7.1 `harness-audit` (read-only)

- **`quick`** (the default, monthly):
  - Adobe's 10 health-check questions;
  - the script-measured level and per-layer scores;
  - if more than 2 fail, it recommends `full`.
- **`full`** (quarterly, or after an incident or major refactor):
  - adds Adobe's 14-item completeness score (0–100, with Adobe's bands);
  - a content-quality pass;
  - the fixed simulated-task probe;
  - the fresh-clone setup proof;
  - re-running sensor fixtures;
  - a comparison with the last log entry.
- **Report order:**
  1. per-layer status and blockers;
  2. one level line, e.g. `Level: Functional · target: Robust · blocked by: …`;
  3. fixes, ranked.
- **Persisted.** One line per run is appended to `docs/harness/AUDIT-LOG.md`, containing only script-measured numbers: date, level, per-layer scores, health score, auto-loaded tokens. Judgements stay in the conversation.
- **Fixes.** The audit makes none. It hands them to `harness-garden`.

### 7.2 Levels

- The plugin **measures** the current level; it can't be declared. The developer sets a **target level** during the Guides section, and that target decides the scope of setup:
  - **Functional** target: Guides and Sensors only.
  - **Robust**: all five layers.
  - **Enterprise**: all five layers, plus CI, CODEOWNERS and audit history.
- The target is recorded in `INVARIANTS.md` as `Harness target: <level>`. The audit never pushes a repo past its target.
- Each level includes the criteria of the one before it:

| Level | Criteria |
|---|---|
| Experimental | `AGENTS.md` + `INVARIANTS.md` exist, `CLAUDE.md` is a shim, `harness-lint` passes |
| Functional | `check` exists and passes on the main branch; enforced automatically (installed git hooks **or** CI); at least one invariant machine-enforced |
| Robust | Every layer has an artifact: plans and session state; guards plus permission rules; at least one project sensor proven, with a fixture; limits honoured; cadence recorded. Every security or data invariant is enforced by a machine or a named human review, never `not yet enforced` |
| Enterprise | CI gate; pinned team settings; CODEOWNERS covering the harness files; audit history with scores holding or improving; every repo in a linked workspace at Functional or higher |

## 8. Guides, Context and Observability details

### 8.1 Pack compatibility (no names)

- The harness provides:
  - `docs/agents/{issue-tracker,domain,triage-labels}.md`;
  - `GLOSSARY.md` (or `GLOSSARY-MAP.md`);
  - `docs/adr/` with `docs/DECISIONS.md`;
  - an `## Agent skills` block in **`AGENTS.md`**;
  - Work Artifacts, which declares the spec, plan, worktree, scratch and working-notes paths;
  - `.gitignore` entries for pack scratch folders the scan finds, plus `.harness/` and `.worktrees/`.
- `CLAUDE.md` stays a strict shim. The guard's refusal message sends any write there to `AGENTS.md → ## Agent skills` or Working Principles.
- `guard_bash.py` also catches shell overwrites and appends to any `CLAUDE.md`: `>`, `>>`, `tee`, `curl -o`, and `cp`/`mv` onto it.
- When the scan finds pack guidance pasted into `CLAUDE.md`, it moves it into `AGENTS.md → Working Principles`, removing duplicates.
- The template keeps generic Working Principles.

### 8.2 Context & State

- `AGENTS.md` gets a **Context loading** table: task type → files to read.
- Plans and progress logs in `docs/plans/` (kept from v1). Unverified claims are marked `[verify]` so invented facts aren't carried forward.
- Work Artifacts gives one line for where packs keep their working notes.

### 8.3 Where checks run (no CI dependency)

| Place | Default | Notes |
|---|---|---|
| Agent hooks (stop gate, guards) | on | Agents only; Claude Code |
| Git hooks: pre-commit runs `check-fast`, pre-push runs `check` | on | If a hook manager exists (husky, lefthook, pre-commit), add to its config. Otherwise use `.githooks/` with `core.hooksPath`, set by `make setup`. The session hook warns when the hooks are off. |
| CI workflow | opt-in | Generated only on a yes, after the explanation is shown. It is the only check nobody can skip; required for Enterprise. |

### 8.4 Observability & Lifecycle

- **Limits:**
  - Defaults: root `AGENTS.md` ≤ 100 lines (warn at 120); auto-loaded files ≤ 3k tokens (warn), 5k (fail).
  - Overridden by `## Context Budget` / `## File Size Budget` in `INVARIANTS.md`.
- **Cadence**, recorded in `AGENTS.md`: quick audit monthly, full audit quarterly or after any incident, garden weekly.
- **Session hook** shows `harness audit is N days old: run /harness-audit` when the last `AUDIT-LOG.md` entry is older than the cadence.
- **CI audit job** only if CI exists and the developer opts in.

## 9. Multi-repo workspace

- **What a workspace is.** A folder that isn't a git repo, holding sibling repos. `harness-workspace` writes **workspace files only**:
  - `harness-workspace.json`, with repos, `owns`, `mergeOrder`, and `harness: present|partial|none`;
  - `AGENTS.md`, a routing table that links each member's `AGENTS.md`;
  - `CLAUDE.md`, which imports the workspace `AGENTS.md` and `INVARIANTS.md` plus each member's `INVARIANTS.md` as `@<repo>/INVARIANTS.md`. It falls back to links, with a warning, if that goes over the token limit;
  - a cross-repo `INVARIANTS.md`: change the contract first, follow the merge order, no breaking API change without a version;
  - read-only cross-repo sensors, e.g. the backend OpenAPI spec matching the frontend client types;
  - `Makefile`/`ws.sh`, `plans/`, `.claude/settings.json`.
- **Harness state per repo:**
  - **present**: `AGENTS.md`, `INVARIANTS.md` and a `check` command;
  - **partial**: some of them;
  - **none**: none of them.

  A repo that is partial or none produces a **warning**, never a failure. Its gate is skipped, visibly, in `check` and the stop gate.
- **Never writes inside a member repo** unless the developer explicitly names that repo (e.g. "create harness for portal"). That runs `harness-init` inside the repo with its own interview.
- **Workspace `make setup`** runs each member's setup in merge order. A workspace `.env` points the frontend and app at the local backend. Repos without a harness are skipped with a warning.

## 10. v1 issues fixed by this design

1. `harness-session/SKILL.md:13` names a pack. **Removed.**
2. A pack setup that writes `## Agent skills` into `CLAUDE.md` gets blocked. **The block now lives in `AGENTS.md`, and the guard redirects there.**
3. Pack scratch folders weren't routed or gitignored. **Fixed by the scan and Work Artifacts.**
4. No layers, level or score. **Fixed in §7.**
5. The scan inventoried files, not layers. **Fixed in §4.**
6. No sensor generation or proof. **Fixed in §6.**
7. In a workspace, a member without a harness was a FAIL and the skill offered to write into it. **Now a warning and no writes.**
8. Member invariants weren't loaded in a workspace. **Now imported.**
9. Limits couldn't be overridden; the Makefile didn't follow Adobe's form. **Fixed.**
10. The shipped `__pycache__/` is deleted, and this folder gets `git init`.
11. Shell writes to `CLAUDE.md` got past the guard. **Fixed.**
12. No dev-environment setup or test data. **Fixed in §5.3–5.4.**

## 11. Plugin self-test

`tests/run.sh` runs these against fixture repos in `tests/fixtures/`: a Node app, a Spring app, a repo with pack leftovers and guidance pasted into `CLAUDE.md`, and a three-repo workspace where one repo has no harness. What it checks:
- lint;
- the scan output;
- guard decisions, including shell writes to `CLAUDE.md`;
- the stop gate;
- `ws.sh` warnings without writes;
- `harness_cmd` resolution;
- sensor fixture re-runs;
- level calculation.

It runs with no network and no Docker. Setup proofs that need Docker are skipped, with a visible note, when Docker is absent.

## 12. Release

Version **2.0.0** (layouts and limits change). The plugin keeps the name `agent-harness`. `install-local.sh` stays as second-priority support for other tools: hooks are Claude Code-only, and sensors run through the runner and git hooks.

## 13. Open risks

- Sensor and setup proofs run real repo tooling; they can be slow on large repos. `quick` audit excludes them.
- The level criteria are this plugin's own definitions, not Adobe's; Adobe gives none. Revisit after the first few repos.
- Detecting dependencies from config is heuristic. Unresolved items fall back to a question, never a guess.
