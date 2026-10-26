# 2. File reference

This section covers every file and folder the harness creates or manages in a repo, and then the workspace files. For each one you get its layer, its purpose, who writes it, who reads it, and whether a human may edit it.

**Writers:** *init* = `harness-init` (copied from `skills/harness-init/assets/` or filled from the scan) · *human* = you · *script* = a harness script at run time · *agent* = a named plugin agent.

## Layout at a glance

```text
repo/
├── AGENTS.md  INVARIANTS.md  CLAUDE.md  GLOSSARY.md        [guides]
├── Makefile (+ include harness.mk)  harness.mk              [tools]
├── .agents/harness.json            (only for a non-make runner) [tools]
├── .agents/skills/                 (repo-specific skills)   [guides]
├── .claude/settings.json                                    [tools]
├── scripts/harness/  cmd.sh lint.sh setup.sh setup-proof.sh local-guard.sh sensor-proof.sh
│   └── sensors/      registry.json  no-prod-data.sh  fixtures/   [sensors]
├── .githooks/        pre-commit  pre-push                    [sensors]
├── docs/  ARCHITECTURE.md TESTING.md SETUP.md DECISIONS.md adr/ plans/ specs/ agents/ harness/AUDIT-LOG.md
├── .github/workflows/harness.yml   (only after a CI yes)   [sensors]
├── <module>/AGENTS.md (+ CLAUDE.md) (only where it earns its place) [guides]
└── gitignored: .harness/  .worktrees/  .env.local  (+ pack scratch folders)
```

## Guides files

### `AGENTS.md` (root)

| Layer | Purpose | Written by | Read by | Humans edit? |
|---|---|---|---|---|
| guides | The map every tool loads: where things are and which commands prove work. It points to detail and does not explain it. Budget ≤ 100 lines (warn), 120 (fail). | init (skeleton, Verification from passing commands, Module map from the scan); human fills the `<…>` and `TODO` parts | every agent via `CLAUDE.md`; `session-context.sh` (Cadence, plan folders); `lint.sh` (size, links, `make` names); `level.py` (Cadence); `verifier` (Verification) | Yes. It is yours. Keep it short. |

Sections in the template:

| Section | Holds | Notes |
|---|---|---|
| Header | "Read INVARIANTS.md first", one-line purpose, link to `docs/ARCHITECTURE.md` | |
| `## Verification` | Short form: done = `make check` (harness-verify first); fast loop `make check-fast`, `make test T=<path>`; all commands: `make help`. Never a list of every target. Another runner: its equivalents and its help command (`just --list`, `npm run`, `task --list`) | `lint.sh` fails if a `make <x>` named here has no target, or if the runner is not make and it names `make` |
| `## Working Principles` | Think before coding · Simplicity first · Surgical changes · Goal-driven · Speak the domain | Pack guidance pasted into `CLAUDE.md` is moved here (duplicates dropped) |
| `## Agent skills` | Precedence (`INVARIANTS.md` > `AGENTS.md` > `.agents/skills/` > plugin skills > tool defaults), artifacts, proof, one process per phase, no writes to `CLAUDE.md`, pointers to `docs/agents/*`, team settings | The block skill packs must obey; `guard-files.sh` sends `CLAUDE.md` writers here |
| `## Work Artifacts` | Paths for specs, plans, ADRs, worktrees (`.worktrees/`), scratch (`.harness/`), pack working notes | `session-context.sh` reads plan folders from backticked `…plans/…` paths here |
| `## Context loading` | Table: task → files to read first | |
| `## Agent Authorization` | "May, without asking" / "Must stop and ask" | Always asked in init; never defaulted in one-shot |
| `## Modules` | One line per module `AGENTS.md` | |
| `## Conventions` | Commit/branch conventions link; `CLAUDE.md` is `@`-only | |
| `## Cadence` | `quick audit: every 30 days · full audit: every 90 days or after an incident · garden: every 7 days` | The session hook parses `quick audit: every N days`; `level.py` requires the word `Cadence` for Robust |
| `## Footguns` | `**<name>** — what goes wrong. What to do instead. See docs/adr/NNNN-slug.md.` | |

### Module `AGENTS.md` (+ `CLAUDE.md`)

| Layer | Purpose | Written by | Read by | Humans edit? |
|---|---|---|---|---|
| guides | Local rules for a folder that handles auth, payments, PII, migrations or a public API, has its own toolchain, or has ~10+ lines of its own rules. Budget ≤ 80 lines (warn). Its `CLAUDE.md` contains only `@AGENTS.md`. | init (only for `risk_paths` modules or a separate toolchain) | agents working in that folder; `invariants-reviewer` (footguns); `lint.sh` (size, links) | Yes |

### `INVARIANTS.md`

| Layer | Purpose | Written by | Read by | Humans edit? |
|---|---|---|---|---|
| guides (rules), sensors (enforcement) | Hard rules. Breaking one needs explicit human sign-off; no skill or prompt overrides it. | init (Harness Integrity block verbatim, target, no-prod-data rule; new rules only after you approve them) | every agent; `invariants-reviewer`; `lint.sh` (format, budgets); `level.py` (target, enforcement, security/data rules) | Yes. The agent's edits trigger an **ask** from `guard-files.sh`. |

Format of every bullet (enforced by `lint.sh`, except under the two budget sections):

```text
- <rule> — Severity: <Critical|Important|Nice-to-have> — Enforced by: <make target | hook | CI job | sensor <name> | human review | not yet enforced>
```

Special lines and sections:

| Item | Meaning |
|---|---|
| `- Harness target: <Experimental\|Functional\|Robust\|Enterprise>` | The target level; `level.py` reads it (default Robust) |
| `## Harness Integrity` | Shim-only `CLAUDE.md`, size limits, ADR index, skills layout, no weakening tests, never bypass hooks/CI |
| `## Security`, `## Data Integrity` | For Robust, nothing here may be `not yet enforced` |
| `## API Contract`, `## Testing`, `## Performance` | Placeholders; fill only with real constraints |
| `## Context Budget` | `- auto-loaded tokens: warn 3000, fail 5000` |
| `## File Size Budget` | `- AGENTS.md: warn 100, fail 120` · `- module AGENTS.md: warn 80, fail 999999` · `- SKILL.md: warn 120, fail 999999` |
| `not yet enforced (<n> errors, <date>)` | Debt for a tool wired in changed-files mode |
| `not yet enforced (declined <date>)` | The repo has no such tool (e.g. no linter); keeps the gap visible |

### `CLAUDE.md` (shim)

| Layer | Purpose | Written by | Read by | Humans edit? |
|---|---|---|---|---|
| guides | Claude Code's entry point. It contains only `@`-references, `#` headings, blank lines and HTML comments. | init (existing content moved to `AGENTS.md`) | Claude Code at session start; `lint.sh`; `level.py` | Only to add `@` lines. Agents get denied by `guard-files.sh` (Edit/Write) and `guard_bash.py` (`>`, `>>`, `tee`, `cp`/`mv`/`install`, `curl -o`, `sed -i`/`perl -i`). |

```markdown
# Claude Code entry point — instructions live in the files below

@AGENTS.md
@INVARIANTS.md
```

### `GLOSSARY.md`

| Layer | Purpose | Written by | Read by | Humans edit? |
|---|---|---|---|---|
| guides | Domain vocabulary: Term · Meaning · Avoid · Code name. For multiple contexts, use `GLOSSARY-MAP.md` → one glossary per context. | init (header only unless you define terms); `harness-glossary` (rows after you say what they mean) | agents (Working Principle 5); `invariants-reviewer`; `harness-glossary`; `harness-garden` (candidates) | Yes. Definitions come from people, never from code. |

### `docs/ARCHITECTURE.md`, `docs/DECISIONS.md`, `docs/adr/`

| File | Layer | Purpose | Written by | Read by | Humans edit? |
|---|---|---|---|---|---|
| `docs/ARCHITECTURE.md` | guides | Components, data flow, boundaries (Mermaid) | init (skeleton) | agents on design tasks; `harness-auditor` | Yes |
| `docs/DECISIONS.md` | guides | Index, one row per ADR: ADR · Decision · Status · Date | init; `harness-garden` adds missing rows | `lint.sh` (every ADR listed, every link exists) | Yes |
| `docs/adr/NNNN-slug.md` | guides | One decision per file (`TEMPLATE.md`, `0001-record-decisions.md` shipped) | human; `harness-learn`, `harness-session`, `harness-glossary` propose | `invariants-reviewer`; `lint.sh` | Yes |

### `docs/agents/*`

| File | Purpose |
|---|---|
| `issue-tracker.md` | How agents use the tracker. One variant is copied: `github` or `gitlab` (detected from `git remote`), or `jira` / `local` (asked). |
| `triage-labels.md` | Label roles: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, … |
| `domain.md` | What to read before exploring: glossary, `DECISIONS.md`, ADRs |

Layer guides; written by init; read by agents and skill packs via `AGENTS.md` → Agent skills pointers. Humans may edit them (fill tracker key and labels).

### `.agents/skills/`

Repo-specific skills (`<name>/SKILL.md` with `name:` and `description:` front matter). `.claude/skills/<name>` may hold **only symlinks** to them. Layer guides; written by humans (or by `install-local.sh` for non-Claude tools); checked by `lint.sh` (section 5) and audit question 10.

## Context & State files

| File | Purpose | Written by | Read by | Humans edit? |
|---|---|---|---|---|
| `docs/plans/TEMPLATE.md` | Plan skeleton: Status · Goal · Acceptance criteria (each proved by a test/command) · Steps (`→ verify:`) · Progress log (append-only) · Decisions | init | `harness-session` | Yes |
| `docs/plans/active/` | Plans in progress | humans and agents (`harness-session`) | `session-context.sh` (matches the branch name, else the newest with unchecked items, ≤ 14 days old); `verifier` (criteria) | Yes |
| `docs/plans/done/` | Finished plans | `harness-session`, `harness-garden` | humans | Yes |
| `docs/specs/` | Designs and specs (`YYYY-MM-DD-<topic>.md`) | humans / skill packs | agents | Yes |

## Tool & Permission files

### `Makefile` and `harness.mk`

| Layer | Purpose | Written by | Read by | Humans edit? |
|---|---|---|---|---|
| tools | One command surface for people, agents, hooks and CI. `harness.mk` is included from the root `Makefile` **after** your own default target. | init copies `harness.mk`, adds the include and the `HARNESS_*` variables | `cmd.sh` (via `make -n <target>`); stop gate; git hooks; `verifier`; CI; `lint.sh` | `Makefile`: yes. `harness.mk`: leave the plugin's copy alone and configure it through variables. |

Targets in `harness.mk`:

| Target | Runs | Always defined? |
|---|---|---|
| `help` | Lists harness targets plus `##`-commented targets of your Makefile (default goal) | yes |
| `check` | `lint typecheck test harness-lint`, then `check: OK` | yes |
| `check-fast` | `lint typecheck` + `$(HARNESS_TEST_CHANGED) $(CHANGED)` if set, else `$(HARNESS_TEST_ALL)` when `HARNESS_TEST_SECS` ≤ 60; target < 60 s | yes |
| `lint` / `typecheck` | `$(HARNESS_LINT)` / `$(HARNESS_TYPECHECK)` | yes |
| `test` | `$(HARNESS_TEST_ALL)`, or `$(HARNESS_TEST_ONE) $(T)` with `T=<path>` | yes |
| `smoke` | `$(HARNESS_SMOKE)` (default prints `smoke: no runnable surface`) | yes |
| `harness-lint` | `bash scripts/harness/lint.sh` | yes |
| `setup` | `$(HARNESS_SETUP)` = `bash scripts/harness/setup.sh` | yes |
| `seed` / `reset` | `local-guard.sh`, then `$(HARNESS_SEED)` / `$(HARNESS_RESET)` | only when the variable is set **above** the include |
| `dev` | `$(HARNESS_DEV)` | only when set above the include |

Variables: `HARNESS_LINT`, `HARNESS_TYPECHECK`, `HARNESS_TEST_ALL`, `HARNESS_TEST_ONE`, `HARNESS_TEST_CHANGED` (usually `bash scripts/harness/related-tests.sh <stack> "<runner>"`), `HARNESS_TEST_SECS` (full-suite baseline seconds), `HARNESS_SMOKE`, `HARNESS_SETUP`, `HARNESS_SEED`, `HARNESS_RESET`, `HARNESS_DEV`, `HARNESS_BASE` (base for `CHANGED`, which also lists untracked new files; default `origin/HEAD`, else `origin/main`, else `origin/master`). To keep a target your Makefile already has, set `HARNESS_DEFINE_<NAME>=0` above the include (`HARNESS_DEFINE_HELP=0`, `HARNESS_DEFINE_CHECK_FAST=0`, …).

Example root `Makefile` after init:

```make
build: ## Build the app
	./gradlew --console=plain build

HARNESS_BASE      = origin/master
HARNESS_LINT      = @echo "lint: none (declined 2026-10-26)"
HARNESS_TEST_ALL  = ./gradlew --console=plain test
HARNESS_TEST_ONE  = ./gradlew --console=plain test --tests
HARNESS_SEED      = psql "$$DATABASE_URL" -f db/seed.sql
include harness.mk
```

Changed-files mode for a tool that already fails on main:

```make
UI_CHANGED   = $(call harness_changed,ui/,ts tsx)
HARNESS_LINT = @if [ -n "$(strip $(UI_CHANGED))" ]; then cd ui && npx eslint $(UI_CHANGED); else echo "lint: no changed UI files"; fi
```

Repo-specific setup steps live in your `Makefile` (or `.agents/harness.json`) as `setup-deps`, `setup-services`, `setup-migrate`; `setup.sh` runs each one only if it resolves. `setup-smith` wires them.

### `.agents/harness.json`

| Layer | Purpose | Written by | Read by | Humans edit? |
|---|---|---|---|---|
| tools | Registers a runner other than make. Each command is printed verbatim; `{T}` (unquoted) is replaced by the shell-quoted test path. | init (only if you pick another runner) | `cmd.sh` first, before make; `lint.sh` (AGENTS.md must name the same runner and commands) | Yes |

```json
{ "runner": "just",
  "commands": { "check": "just check", "check-fast": "just quick", "test": "just test {T}",
                "setup": "just bootstrap", "seed": "just seed", "reset": "just reset",
                "smoke": "just smoke", "dev": "just dev" },
  "help": "just --list" }
```

`help` is optional: the runner's list command, named in `AGENTS.md` Verification ("All commands: `just --list`") and returned by `cmd.sh <dir> help` when `commands.help` is absent.

### `.claude/settings.json`

| Layer | Purpose | Written by | Read by | Humans edit? |
|---|---|---|---|---|
| tools | Team-shared: pins the plugin (`extraKnownMarketplaces`, `enabledPlugins`) and adds permission **deny** rules on top of the guard hooks | init after you approve the rules (Claude Code may refuse the write; then you add it yourself from the shown JSON) | Claude Code; `level.py` (deny rules → Robust, pinned plugin → Enterprise) | Yes. Review it like code. |

Proposed deny rules: secrets files, `Read(./**/secrets/**)`, `Read(./**/*.pem)`, `Read(./**/*.key)`, plus dangerous infra/production commands found in the repo (e.g. `Bash(terraform apply:*)`), each with its `file:line`. Allow rules for the runner (e.g. `Bash(make check:*)`). The `.env` rules deny `.env`, `.env.local` and real environment files, while `.env.example` / `.env.sample` stay readable.

### `scripts/harness/*`

All are copied by init (or `install-local.sh`) and run from the repo root. Leave them alone unless you are fixing a bug. Changes belong upstream in the plugin: after a plugin update, `harness-init` refreshes unmodified copies (user guide → Updating).

| File | Layer | Purpose | Read/run by |
|---|---|---|---|
| `cmd.sh` | tools | Resolves a target to a command: `.agents/harness.json` first, else `make -s -C <dir> <target>` if `make -n <target>` succeeds. Usage `cmd.sh <dir> <target> [T]`. Exit 3 = not wired, 4 = make missing (both are **not** a pass). | git hooks, `setup.sh`, `setup-proof.sh`, skills, `verifier`, `harness-auditor` |
| `lint.sh` | observability | `harness-lint`: core files exist; `CLAUDE.md` shim; size and token budgets; ADR index; skills layout; relative links; `make`/runner names in AGENTS.md exist; `INVARIANTS.md` format; TODO/`[verify]` warnings; sensor recheck; `.gitignore` covers `.harness/`. Prints `harness-lint: OK (≈N auto-loaded tokens)` or `FAIL` lines. | `make check`, `level.py`, init, garden, learn |
| `setup.sh` | tools | `make setup`: prereq versions (`.nvmrc`, `.python-version`, `.sdkmanrc`, `.tool-versions`), registry sign-in hints, `.env` from `.env.example` if missing, `.env.local` with worktree values, then `setup-deps`, services (`docker compose … up -d`), `setup-migrate`, `seed`, git hooks, `smoke`. Never `sudo`, never fetches secrets. | `make setup`, `setup-proof.sh`, workspace `ws.sh setup` |
| `setup-proof.sh` | tools | Clones committed HEAD to a temp folder, resolves and runs `setup` there under its own compose project, tears down. Prints `setup-proof: OK`, `FAIL (<step>)` or `SKIPPED (docker not available)`. `HARNESS_PROOF_KEEP_ENV=1` copies `.env.local` in. | `setup-smith`, init step 5, `harness-audit full` |
| `sensor-proof.sh` | sensors | `sensor-proof.sh <name>` (3-step proof) or `--recheck` (fixture fires, clean passes, for all sensors) | `sensor-smith`, `lint.sh`, `level.py`, audit |
| `local-guard.sh` | tools | Refuses `seed`/`reset` unless every DB-like host is local. Checks env, `.env` and `.env.local` (`DATABASE_URL`, DB-scheme `*_URL`, `DB_HOST`, `*_DB_HOST`, `PGHOST`, `MYSQL_HOST`, `MONGO_URL`, `REDIS_URL`) and Spring `spring.datasource.url` in `src/main/resources/application.properties|yml` and the `application-local*`, `-dev*`, `-test*` profiles, plus every profile named in `SPRING_PROFILES_ACTIVE` (env, `.env`, `.env.local`): an active `prod` profile is read and its non-local hosts refused. Inactive profiles are not read. Oracle thin URLs (`jdbc:oracle:thin:@host:1521/X`, `@//host`) are parsed for their host. | `make seed`, `make reset` |
| `related-tests.sh` | sensors | `HARNESS_TEST_CHANGED` helper: `related-tests.sh [-C <module>] <stack> "<runner>" <changed files>` runs the tests a change can break. jest/vitest: their related-tests lookup; go: each changed package; maven/gradle: `Foo` → `FooTest`/`FooTests`/`FooIT`/`TestFoo` plus tests naming `Foo`; pytest: `test_foo.py`/`foo_test.py`, tests naming `foo`, else tests naming its package; node: `foo.test.js` plus tests naming `foo`. Nothing related → `tests: no …`, exit 0 | `check-fast` (`HARNESS_TEST_CHANGED`) |
| `assets.json` | tools | Manifest of the plugin-owned copies: `{"plugin": "<version>", "sha256": {"<path>": "<sha256>"}}` for `scripts/harness/*` (not `sensors/registry.json` or fixtures), `.githooks/*` and `harness.mk`. A copy whose hash matches is unmodified and may be refreshed; any other content is `modified` and left alone. No marker lines are added to the files themselves. Written by `assets.py install`/`refresh`; commit it. | `assets.py`, session hook, `harness-audit` |
| `sensors/registry.json` | sensors | `{"sensors":[{"name","severity","invariant","run","mode","clean","fixture","dest"}]}`. `mode: paths` substitutes `{paths}`; `mode: copy` copies fixture files into `dest`, runs, then removes them. | `sensor-proof.sh`, `level.py` |
| `sensors/no-prod-data.sh` | sensors | `no-prod-data.sh <path…>`: flags real-looking emails (except `@example.*`, `.test`, `.invalid`, `.local`), `prod`/`production` in host or URL contexts only (after `@` or `//`, or as a `host`/`*_HOST`/`url` value; prose and comments are ignored), `rds.amazonaws.com` hosts, real-looking phone numbers, and `.sql`/`.dump` files > 1 MB. Output `file:line: reason — use synthetic data (INVARIANTS.md Data Integrity)`. | `make check` once wired, `sensor-proof.sh` |
| `sensors/fixtures/<name>/` | sensors | Planted violations, e.g. `no-prod-data/seed.sql` with `jane@acme.com`. Never edit them to make a proof pass. | `sensor-proof.sh` |

Local-host rules in `local-guard.sh`: `localhost`, `::1`, `host.docker.internal`, `*.local`, `*.test`, `*.localhost`, `127.x.x.x` (digits only), and single-label names that are a service in a compose file in the repo (`docker-compose*.yml`, `compose*.yml`) are local. Any other single-label name (e.g. `prod`) is refused with `<host> is not a localhost name or a service in this repo's compose files`. Every host in a multi-host URL is checked.

### `.env`, `.env.local`, `compose.harness.yml`

| File | Purpose | Written by | Humans edit? |
|---|---|---|---|
| `.env` | Real local values. Created from `.env.example` by `setup.sh` only if missing; never overwritten. | `setup.sh` (first copy), then you | Yes. Agents are denied by `guard-files.sh`. |
| `.env.example` / `.env.sample` | Variable names and safe defaults; `*_PORT` and `DB_NAME` here drive worktree isolation | you | Yes. Agents may write these. |
| `.env.local` | Gitignored, per-checkout values: `COMPOSE_PROJECT_NAME`, `*_PORT`, `DB_NAME=<db>_<project>`. Your other lines are kept on re-run. `HARNESS_SHARED_SERVICES=1` here is honoured. | `setup.sh` | Yes (managed keys are rewritten) |
| `compose.harness.yml` | Local-only services when the repo has no compose file | `setup-smith`, **only after an explicit yes** (never by "defaults" or one-shot) | Yes |

### `docs/SETUP.md`

Layer tools. The dependency inventory: one row per external dependency (Dependency · Kind · Version · Source/evidence · Local mode `service|stub|shared-env|not needed` · Details from). Resolved rows cite `file:line`; unresolved rows record where you said to read about them. Written by init and `setup-smith`; read by developers and `harness-auditor`. Humans may edit it.

## Sensors files

| File | Purpose | Written by | Read by | Humans edit? |
|---|---|---|---|---|
| `.githooks/pre-commit` | Runs resolved `check-fast`. Prints `harness: setup in progress, skipping` while `.harness/init-state.json` lacks `"gate_wired": true`; skips with a one-line message (`harness: check-fast not wired, skipping` / `harness: scripts/harness/cmd.sh missing, skipping`) when the target isn't wired or `cmd.sh` is missing. | init / `install-local.sh` | git (via `core.hooksPath .githooks`, set by `make setup`) or your hook manager | Prefer not |
| `.githooks/pre-push` | Same, with `check` | same | same | Prefer not |
| Hook manager config | husky: `bash .githooks/pre-commit  # harness check-fast` in `.husky/pre-commit`; lefthook: `harness-check-fast` / `harness-check` commands; pre-commit: `repo: local` hooks `harness-check-fast`, `harness-check` (`stages: [pre-push]`) | init (Sensors layer) | the manager | Yes |
| `docs/TESTING.md` | Test layout, what must be tested, fixtures and mocks, "a test proves a change only if it fails without it" | init (skeleton) | agents writing tests | Yes |
| `.github/workflows/harness.yml` | CI: `make harness-lint`, then `make check` on PRs and pushes to main; weekly lint-only run | init, **only after a CI yes** | CI; `level.py` (Enterprise) | Yes (add toolchain setup) |

## Observability files

| File | Purpose | Written by | Read by | Humans edit? |
|---|---|---|---|---|
| `docs/harness/AUDIT-LOG.md` | One line per audit: `\| date \| level \| g=… s=… c=… t=… o=… \| health=N \| tokens=N \|` | only `level.py --log` (init final report, `harness-audit`) | `session-context.sh` (age vs Cadence), `level.py` (Enterprise trend), `harness-audit full` (compare) | **No.** Script-measured only. |

## Gitignored state

`assets/gitignore.append` adds `.harness/`, `.worktrees/`, `.env.local`. Init also ignores pack scratch folders the scan found.

| Path | Purpose | Written by | Read by |
|---|---|---|---|
| `.harness/scan.json` | Scan result keyed to `head`: `stacks`, `modules`, `commands[{module,role,cmd,source,baseline}]`, `versions`, `services`, `env_vars`, `migrations`, `seeds`, `hook_manager`, `ci`, `harness_files`, `pasted_guidance`, `pack_folders`, `risk_paths`, `is_worktree` | `scan.py --write` (init, `repo-cartographer`); init adds `baseline` | init (resume), audit, garden, `sensor-smith`, `setup-smith` |
| `.harness/init-state.json` | `{"layers_done":[…], "answers":{…}, "gate_wired":bool, "gate_reason":"…", "target":"…"}`. Written with `"gate_wired": false` **before** any harness file; set `true` only when `check-fast` resolved and passed. | `harness-init` | init (resume); stop gate and git hooks (silent until `gate_wired` is true); session hook ("setup in progress" while a layer in scope for `target` is missing: Experimental/Functional need `guides`, `sensors`; Robust/Enterprise or no target need all five; warns once if the file is unreadable; "gate not wired — <gate_reason>" once all layers are done but `gate_wired` is not true) |
| `.harness/last-check` | `<fingerprint> pass <date>` after a green stop-gate run | `stop-gate.sh` | `level.py` without `--run-checks` |
| `.harness/last-green-repo` | Fingerprint of the last green tree, so an unchanged tree isn't re-checked | `stop-gate.sh` | `stop-gate.sh` |
| `.harness/last-fail-repo`, `.harness/stop-blocks` | Fingerprint of the last blocked tree and the count of blocks in a row (re-check bound, max 3) | `stop-gate.sh` | `stop-gate.sh` |
| `.worktrees/` | Git worktrees (Work Artifacts) | you / skill packs | `lint.sh` fails if it exists but isn't ignored |

Delete `.harness/` freely except mid-init (you'd lose resume state).

## Workspace files

These are written only in the workspace folder by `/agent-harness:harness-workspace`, never inside a member repo. Details are in [04-workspace.md](04-workspace.md).

| File | Layer | Purpose | Written by | Read by | Humans edit? |
|---|---|---|---|---|---|
| `harness-workspace.json` | guides/tools | Manifest: `name`, `issueKey`, `repos[{name,path,remote,base,harness,owns}]`, `mergeOrder` | skill | `ws.sh`, session hook, stop gate, `level.py`, `cross-repo-reviewer` | Yes (agent edits trigger an ask) |
| `AGENTS.md` | guides | Routing table (repo → path → owns → its `AGENTS.md`), Verification, Cross-repo rules, Work Artifacts, Agent skills, Authorization; `## Member invariants` links when imports exceed the budget | skill; `ws.sh claude-md` appends links | agents | Yes |
| `CLAUDE.md` | guides | `@AGENTS.md`, `@INVARIANTS.md`, `@<repo>/INVARIANTS.md` per present member | `make claude-md` | Claude Code | No, regenerate it |
| `INVARIANTS.md` | guides | Contract first, merge order, no breaking API change without a version, no cross-repo imports, one branch name | skill | agents, `cross-repo-reviewer` | Yes |
| `Makefile` + `ws.sh` | tools | `status`, `changed`, `check`, `check-fast`, `setup`, `claude-md`, `test R= T=`, `branch B= R=`, `bootstrap`, `harness-lint` | skill | you, agents, `harness-verify` | Prefer not |
| `scripts/harness/cmd.sh` | tools | Resolver used by `ws.sh` for each member | skill | `ws.sh` | No |
| `scripts/harness/assets.json` | tools | sha256 of the workspace copies of `cmd.sh` and `ws.sh`, so a plugin update can refresh them | `assets.py` | session hook | No |
| `.env.workspace` | tools | Local wiring, e.g. `API_BASE_URL=http://localhost:<port>` from the backend's `.env.local` | skill | you (copy into the member yourself) | Yes |
| `plans/` | context | `TEMPLATE.md`, `active/`, `done/` for cross-repo plans | skill | session hook, `harness-session`, `cross-repo-reviewer` | Yes |
| `.claude/settings.json` | tools | Pins the plugin; denies secrets reads across members | skill (or you, if the write is refused) | Claude Code | Yes |
| `.harness/` | — | Stop-gate state per member: `last-green-<name>`, `last-check-<name>` | `stop-gate.sh` | stop gate, `level.py` | — |
