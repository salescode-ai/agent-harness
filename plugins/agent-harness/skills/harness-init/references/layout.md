# Harness Layout and Ownership

## Files

Layer tags: `[guides]` `[tools]` `[sensors]` `[context]` `[observability]`.

```text
repo/
├── AGENTS.md              [guides]   the map every tool loads; ≤ 100 lines; Verification, Agent skills, Work Artifacts, Context loading, Cadence
├── INVARIANTS.md          [guides]   hard rules: "<rule> — Severity: <tier> — Enforced by: <…>"; "Harness target: <level>"
├── CLAUDE.md              [guides]   @AGENTS.md  @INVARIANTS.md   — nothing else
├── GLOSSARY.md            [guides]   domain vocabulary (multi-context: GLOSSARY-MAP.md → per-module GLOSSARY.md)
├── Makefile               [tools]    the repo's own targets + `include harness.mk`
├── harness.mk             [tools]    check, check-fast, test T=, smoke, setup, seed, reset, dev, dev-check, dev-stop, harness-lint, help
├── .agents/harness.json   [tools]    only when the runner is not make: {"runner", "commands", "help"?}
├── .claude/settings.json  [tools]    agent-harness plugin + permission rules (team-shared)
├── .agents/skills/        [guides]   repo-specific skills only; .claude/skills/<name> are symlinks to these
├── scripts/harness/       [tools]    cmd.sh (command resolver), lint.sh, related-tests.sh, setup.sh, setup-proof.sh, local-guard.sh, dev-check.sh
│   ├── assets.json        [tools]    sha256 of each plugin-owned copy (scripts, .githooks/, harness.mk): lets upgrades refresh unmodified copies
│   └── sensors/           [sensors]  registry.json, project sensors, fixtures/ (planted violations), sensor-proof.sh runs them;
│                                     lib/diffscan.py (plugin-owned): the added lines, for sensors that check only new code
├── .githooks/             [sensors]  pre-commit → check-fast, pre-push → check (or the repo's hook manager)
├── docs/
│   ├── SETUP.md           [tools]    dependency inventory: resolved (file:line) and unresolved (where to read)
│   ├── ARCHITECTURE.md    [guides]   components, data flow, boundaries (Mermaid)
│   ├── TESTING.md         [sensors]  test layout, what must be tested, fixtures
│   ├── DECISIONS.md       [guides]   index: one row per ADR
│   ├── adr/NNNN-slug.md   [guides]   one decision per file
│   ├── plans/             [context]  execution plans (active/ and done/), plan template
│   ├── specs/             [context]  designs and specs
│   ├── agents/            [guides]   issue-tracker.md, domain.md, triage-labels.md
│   └── harness/AUDIT-LOG.md [observability] one script-measured line per audit
├── .github/workflows/harness.yml [sensors] only after a CI opt-in
└── src/<module>/AGENTS.md [guides]   only where it earns its place
```

Ignored: `.harness/` (`scan.json`, `init-state.json`, hook state), `.worktrees/`, pack scratch folders.

## Ownership — one owner per fact

| Fact | Owner | Everyone else |
|---|---|---|
| Hard constraints | `INVARIANTS.md` | link |
| What proves "done"; how to run tests | `AGENTS.md` Verification → `harness.mk` or `.agents/harness.json` | name the target |
| How skills and plugins must behave | `AGENTS.md` Agent skills | — |
| How to get a working dev setup | `docs/SETUP.md` → `make setup` | link |
| Where specs, plans, ADRs, worktrees go | `AGENTS.md` Work Artifacts | link |
| Who may commit/merge; what needs a human | `AGENTS.md` Agent Authorization | link |
| Known traps | `AGENTS.md` Footguns (root) or module `AGENTS.md` | link to ADR |
| System structure | `docs/ARCHITECTURE.md` | one sentence + link |
| Why a decision was made | `docs/adr/NNNN-*.md` | link via `docs/DECISIONS.md` |
| Domain terms | `GLOSSARY.md` | use the term |
| Test strategy | `docs/TESTING.md` | link |
| Work in progress | `docs/plans/active/<plan>.md` | link |

## Size budgets

| Item | Budget | Why |
|---|---|---|
| Auto-loaded set (`CLAUDE.md` + root `AGENTS.md` + `INVARIANTS.md`) | ≤ 3,000 tokens (warn), 5,000 (fail) | Loaded on every turn; crowds out the task |
| Root `AGENTS.md` | ≤ 100 lines (warn 120) | It is a map, not a manual |
| Module `AGENTS.md` | ≤ 80 lines | Local rules only |
| `SKILL.md` | ≤ 120 lines; detail in `references/` | Progressive disclosure |

## Command contract

Every caller (hooks, verifier, git hooks, audit) resolves a target with `bash scripts/harness/cmd.sh . <target>` and `eval`s the printed command: `.agents/harness.json` first, else `make <target>`.

| Target | Must | Used by |
|---|---|---|
| `check` | lint + typecheck + full tests; exit non-zero on any failure | verifier agent, CI, "done" |
| `check-fast` | lint + typecheck + the tests related to changed files (sources too); < 60 s | stop-gate hook |
| `test` | all tests; `T=<path>` runs one file/test | TDD loops in every pack |
| `smoke` | start the app and hit one real path (if there is a runnable surface) | verifier, session start |
| `setup` | `scripts/harness/setup.sh`: safe to re-run, isolated per worktree | developers, setup-proof |
| `dev-check` | with `HARNESS_HEALTH`: start dev, wait until healthy, run `RUN='<cmd>'`, always stop | agents checking a running app (the guard refuses a long-lived `make dev`) |
| `seed` / `reset` | reload / wipe and re-seed local data; refuse non-local targets | developers |
| `harness-lint` | `bash scripts/harness/lint.sh` | CI, harness-garden |

Output rule: success is quiet (one line), failure is loud (the error and the file). Agents read every byte.

**Changed-files mode** (for a tool that already fails on `main`): `harness.mk` provides
`$(call harness_changed,<dir>/,<ext> <ext>)` — the changed files under `<dir>` with those extensions, paths relative to `<dir>`.
Example for a UI with legacy lint debt:

```make
UI_CHANGED   = $(call harness_changed,ui/,ts tsx)
HARNESS_LINT = @if [ -n "$(strip $(UI_CHANGED))" ]; then cd ui && npx eslint $(UI_CHANGED); else echo "lint: no changed UI files"; fi
```

New and edited files must be clean; untouched legacy files don't block anyone. Record the debt in `INVARIANTS.md` so it is paid down deliberately.

**Declined tool** (the repo has no linter or type checker, e.g. many Maven or CRA projects): don't leave the failing default. Write

```make
HARNESS_LINT = @echo "lint: none (declined 2026-10-26)"
```

and pair it with `- Code is linted — Severity: Important — Enforced by: not yet enforced (declined 2026-10-26)` in `INVARIANTS.md`, so the gap stays visible to audits.

**Skipped tool** (baseline `skipped`: the environment can't run it, or it timed out): wire it the same way, `HARNESS_LINT = @echo "lint: skipped (no JDK 11 on this host, 2026-10-26)"`, with `Enforced by: not yet enforced (skipped: <why>, <date>)`. The default `not configured && false` would keep `check` red and the gate unwired forever.

**Tests in check-fast.** Record each baseline's wall-clock seconds (`baseline_secs` in `scan.json`). Then:

- full-suite baseline `pass` in ≤ 60 s → `HARNESS_TEST_SECS = <seconds>`: check-fast runs `HARNESS_TEST_ALL`;
- otherwise map changed files to tests with `scripts/harness/related-tests.sh [-C <module>] <stack> "<runner>"`, which receives the changed files:

```make
HARNESS_TEST_CHANGED = bash scripts/harness/related-tests.sh maven "./mvnw -B -q test"          # Foo.java → FooTest/FooTests/FooIT + tests naming Foo
HARNESS_TEST_CHANGED = bash scripts/harness/related-tests.sh gradle "./gradlew test --console=plain -q"  # same, as --tests
HARNESS_TEST_CHANGED = bash scripts/harness/related-tests.sh go "go test"                       # each changed package
HARNESS_TEST_CHANGED = bash scripts/harness/related-tests.sh pytest "python3 -m pytest -q"       # test_foo.py / foo_test.py, tests naming foo, else the package's
HARNESS_TEST_CHANGED = bash scripts/harness/related-tests.sh jest "CI=true npx jest"            # --findRelatedTests (vitest: related --run; node: node --test)
HARNESS_TEST_CHANGED = bash scripts/harness/related-tests.sh -C backend maven "mvn -B -q test"  # monorepo module: runs inside backend/
```

A failing suite (legacy debt) still uses the helper: only the tests of what you touched run. `HARNESS_TEST_CHANGED` wins over `HARNESS_TEST_SECS`; with both empty check-fast runs no tests. A runner that picks its own tests sets `HARNESS_TEST_CHANGED_ARGS =` (empty) so check-fast doesn't compute the changed-files list. `harness-lint` warns `check-fast tests nothing for <file>` for each changed source file no test selects (it asks `make harness-test-plan`, which runs no tests), and once when a custom `HARNESS_TEST_CHANGED` bypasses `related-tests.sh` (`HARNESS_TEST_CHANGED_CONFIRMED = 1` once the developer has checked that selector). Source files are the extensions of the stacks whose build files the repo has; `scripts/harness/` is never source.

**Test commands keep their exit code.** `make test T=<path>` appends T to `HARNESS_TEST_ONE`, and check-fast appends the changed files to `HARNESS_TEST_CHANGED`. A runner that can't take a trailing argument puts `{T}` / `{CHANGED}` where it goes; harness.mk then substitutes it instead of appending (`-Dtest='{T}'`, `--tests {T}`). Never end a value in `; :` to swallow the argument: that discards the exit code, so the target is green on failing tests (harness-lint warns). If you must swallow it, end in `&& :`. T is data, not code: harness.mk keeps it literal and accepts only names, paths, `#method`, commas and globs (`[A-Za-z0-9_./#,*?:@+=[] -]`, no word starting with `-`), and changed file names outside that set are left out of check-fast. A selector that runs **0 tests** must fail too, or a typo passes:

| Stack | `HARNESS_TEST_ONE` must fail on 0 tests |
|---|---|
| Maven | no `-Dsurefire.failIfNoSpecifiedTests=false` here (keep it in changed-files mode only, where related-tests.sh adds it). JUnit 4 classes without the vintage engine, or a missing `#method`, still run 0 tests and exit 0, so check the reports: `mkdir -p .harness && touch .harness/test-one.stamp && ./mvnw -B -q test -Dtest="$$(basename '{T}' .java)" && { find . -path '*/surefire-reports/TEST-*.xml' -newer .harness/test-one.stamp -exec grep -l 'tests="[1-9]' {} + \| grep -q . \|\| { echo "test: 0 tests ran for {T}" >&2; exit 1; }; }` |
| Gradle | `--tests {T}` fails on no match by default; never set `filter.failOnNoMatchingTests = false` |
| pytest | exit code 5 means "no tests collected"; never map it to 0 (`\|\| [ $$? -eq 5 ]`) |
| Jest / Vitest | never set `--passWithNoTests` on `HARNESS_TEST_ONE` (related-tests.sh sets it for changed-files mode only) |

`bash scripts/harness/gate-proof.sh` proves all of this: in a scratch worktree it plants one failing test (JUnit 5, pytest or Vitest/Jest) and checks that `test T=<it>`, `test T=<no such test>` and check-fast each exit non-zero. harness-init and harness-upgrade run it and record `gate_red_proven` in `.harness/init-state.json`; level.py counts a gate never proven red as a sensors gap.

`HARNESS_SEED`, `HARNESS_RESET` and `HARNESS_DEV` must be set **above** `include harness.mk`: their targets are defined only when set, so an unconfigured repo has no `seed` target and `make setup` skips that step. The same holds for `HARNESS_HEALTH`, which (with `HARNESS_DEV`) defines `dev-check` and `dev-stop`. A server app whose smoke boots it: `HARNESS_SETUP_SMOKE = 0`. A step that cannot finish without a person (no DB configured, a missing credential) exits 0 and prints a line `needs you: <what>` (or `<target>: needs you: <what>`): setup lists it under "needs you", shows the step as `✓ (needs you)` and skips smoke, while a fresh clone still passes `setup-proof`. A repo's own `setup-services` gets none of the `*_PORT` values setup.sh picked as environment variables: Docker Compose gives shell variables precedence over `--env-file`, so they would override whatever ports that target chooses. It reads `.env.local` (or picks its own and writes them there); setup.sh re-reads `.env.local` for `setup-migrate` and `seed`.

## Module AGENTS.md — create only if one is true

- handles auth, payments, PII, migrations, or a public API contract
- has a different toolchain from the root
- has at least ~10 lines of rules or traps not stated anywhere upstream

Otherwise add one line to root Footguns instead.
