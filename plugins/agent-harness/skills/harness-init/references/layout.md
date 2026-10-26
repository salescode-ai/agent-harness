# Harness Layout and Ownership

## Files

```text
repo/
├── AGENTS.md              # the map every tool loads; < 100 lines; points, doesn't explain
├── INVARIANTS.md          # hard rules, each with "Enforced by:"
├── CLAUDE.md              # @AGENTS.md  @INVARIANTS.md   — nothing else
├── GLOSSARY.md            # domain vocabulary (multi-context: GLOSSARY-MAP.md → per-module GLOSSARY.md)
├── Makefile               # the only commands agents run: check, check-fast, test T=, smoke, harness-lint
├── .claude/settings.json  # agent-harness plugin + permissions (team-shared)
├── .agents/skills/        # repo-specific skills only; .claude/skills/<name> are symlinks to these
├── docs/
│   ├── ARCHITECTURE.md    # components, data flow, boundaries (Mermaid)
│   ├── TESTING.md         # test layout, what must be tested, fixtures
│   ├── DECISIONS.md       # index: one row per ADR
│   ├── adr/NNNN-slug.md   # one decision per file
│   ├── plans/             # execution plans (active/ and done/), plan template
│   ├── specs/             # designs and specs
│   └── agents/            # issue-tracker.md, domain.md (read by any skill that files tickets or names things)
├── scripts/harness/lint.sh  # structural tests for the harness itself
├── .github/workflows/harness.yml
└── src/<module>/AGENTS.md   # only where it earns its place
```

Ignored: `.harness/` (hook state, session scratch), `.worktrees/`.

## Ownership — one owner per fact

| Fact | Owner | Everyone else |
|---|---|---|
| Hard constraints | `INVARIANTS.md` | link |
| What proves "done"; how to run tests | `AGENTS.md` Verification → `Makefile` | name the make target |
| How skills and plugins must behave | `AGENTS.md` Skills and plugins | — |
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

## Makefile contract

| Target | Must | Used by |
|---|---|---|
| `check` | lint + typecheck + full tests; exit non-zero on any failure | verifier agent, CI, "done" |
| `check-fast` | lint + typecheck + tests touching changed files; < 60 s | stop-gate hook |
| `test` | all tests; `T=<path>` runs one file/test | TDD loops in every pack |
| `smoke` | start the app and hit one real path (if there is a runnable surface) | verifier, session start |
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

## Module AGENTS.md — create only if one is true

- handles auth, payments, PII, migrations, or a public API contract
- has a different toolchain from the root
- has at least ~10 lines of rules or traps not stated anywhere upstream

Otherwise add one line to root Footguns instead.
