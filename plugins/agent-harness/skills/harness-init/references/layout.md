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
├── harness.mk             [tools]    check, check-fast, test T=, smoke, setup, seed, reset, dev, harness-lint, help
├── .agents/harness.json   [tools]    only when the runner is not make: {"runner", "commands"}
├── .claude/settings.json  [tools]    agent-harness plugin + permission rules (team-shared)
├── .agents/skills/        [guides]   repo-specific skills only; .claude/skills/<name> are symlinks to these
├── scripts/harness/       [tools]    cmd.sh (command resolver), lint.sh, setup.sh, setup-proof.sh, local-guard.sh
│   └── sensors/           [sensors]  registry.json, project sensors, fixtures/ (planted violations), sensor-proof.sh runs them
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
| `check-fast` | lint + typecheck + tests touching changed files; < 60 s | stop-gate hook |
| `test` | all tests; `T=<path>` runs one file/test | TDD loops in every pack |
| `smoke` | start the app and hit one real path (if there is a runnable surface) | verifier, session start |
| `setup` | `scripts/harness/setup.sh`: safe to re-run, isolated per worktree | developers, setup-proof |
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

`HARNESS_SEED`, `HARNESS_RESET` and `HARNESS_DEV` must be set **above** `include harness.mk`: their targets are defined only when set, so an unconfigured repo has no `seed` target and `make setup` skips that step.

## Module AGENTS.md — create only if one is true

- handles auth, payments, PII, migrations, or a public API contract
- has a different toolchain from the root
- has at least ~10 lines of rules or traps not stated anywhere upstream

Otherwise add one line to root Footguns instead.
