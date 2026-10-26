# Migrations registry

The registry lives in `scripts/migrate.py` (`MIGRATIONS`). Each entry is `{id, since, layer, detect + apply}`: one function that looks at the repo and returns only the edits still needed, so running it twice changes nothing the second time. Kinds:

- **auto** — safe without asking: a new file, a plugin template whose sha256 matches a released copy (`scripts/asset-history.json`), or local state in `.harness/` (gitignored).
- **propose** — an edit to a repo-owned file. All of them are shown as **one** unified diff (`migrate.py diff`) and written only after a single yes (`migrate.py accept [--skip id,…]`). When two migrations touch one file, the diff already holds both.
- **manual** — needs a decision or a run the script cannot make (timing a test suite, choosing skipped vs declined). The skill asks; the line says what to do.

Plugin-owned scripts (`scripts/harness/*`, `.githooks/*`, `harness.mk`, `ws.sh`) are not migrations: `assets.py install` refreshes unmodified copies and adds missing ones. The recorded version is `"plugin"` in `scripts/harness/assets.json`, written by every `assets.py install|refresh`.

| id | since | layer | kind | detects | does |
|---|---|---|---|---|---|
| `templates` | 2.0.4 | context | auto / propose | `docs/plans/TEMPLATE.md`, `docs/adr/TEMPLATE.md` (workspace: `plans/TEMPLATE.md`) differ from the plugin's | unedited released copy → replaced (auto); edited → add the `Ticket:` line, the plan's `**Evidence**: local .harness/evidence/…` line, drop an empty 2.0.4-dev `## Verification` (propose) |
| `plan-ticket` | 2.0.4 | context | propose | an active plan whose `Ticket:` is missing or a placeholder (lint fails on it) | sets the key from the file name (`YYYY-MM-DD-KEY-12-…`), else from the branch (`KEY-12-…`, when it matches the plan), else `none (no ticket recorded before 2.0.4)` — ask for the real key before accepting |
| `plan-verification-empty` | 2.0.4 | context | propose | an active plan holding the **empty** `## Verification` section of the 2.0.4-dev template | removes it (evidence is local now); a section with entries is left alone |
| `decisions-ticket` | 2.0.4 | context | propose | `docs/DECISIONS.md` table without a `Ticket` column | adds the column; existing rows get `none` |
| `agents-verification` | 2.0.4 | guides | propose / manual | `AGENTS.md` (workspace `AGENTS.md`) Verification in the 2.0.0–2.0.3 long form | replaces the released bullets with the short form, using the registered runner's commands and help (`just --list`, `npm run`, `task --list`); bullets the developer added stay. Edited long form → manual |
| `harness-json-help` | 2.0.4 | tools | propose / manual | `.agents/harness.json` registers a runner but has no `"help"` | adds `"help"` for just / task / npm / pnpm / yarn; other runners → manual |
| `env-deny` | 2.0.1 | tools | propose | `.claude/settings.json` denies `Read(./.env.*)` (it also hid `.env.example`) | replaces it with the real env files: `**/.env`, `**/.env.local`, `**/.env.*.local`, `**/.env.prod*`, `**/.env.staging*` |
| `harness-base` | 2.0.1 | tools | propose / manual | `HARNESS_BASE = <ref>` in the `Makefile` names a ref that does not exist | the derived base: `origin/HEAD`, else `origin/main`, else `origin/master`, else the upstream; none found → manual |
| `init-state-target` | 2.0.2 | context | auto | `.harness/init-state.json` without `"target"` while `INVARIANTS.md` says `Harness target: <level>` | copies the target, so progress is judged by the target's layers |
| `check-fast-tests` | 2.0.3 | sensors | manual | make runner, test files exist, neither `HARNESS_TEST_CHANGED` nor `HARNESS_TEST_SECS` set | time the full suite (non-interactive form): ≤ 60 s → `HARNESS_TEST_SECS = <secs>`; else `HARNESS_TEST_CHANGED = bash scripts/harness/related-tests.sh [-C <module>] <stack> "<runner>"` (`harness-init/references/layout.md`). Propose the Makefile line as a diff |
| `tool-wiring` | 2.0.3 | tools | manual | `HARNESS_LINT` / `HARNESS_TEST_ALL` unset (harness.mk's failing default) | wire the real command if it passes; environment can't run it → `@echo "<tool>: skipped (<why>, <date>)"`; the repo has none → `@echo "<tool>: none (declined <date>)"`; either way add a `not yet enforced (…)` invariant |
| `gate-wired` | 2.0.3 | sensors | manual | `init-state.json` without `"gate_wired": true` | step 3 of the skill: check-fast resolved and passed → `true`, else `"gate_reason"` |
| `harness-mk-test-plan` | 2.0.4 | sensors | manual | `harness.mk` without the `harness-test-plan` target after the refresh (a locally modified copy) | merge the target from the plugin copy by hand (`diff harness.mk <plugin>/skills/harness-init/assets/harness.mk`) |

## Adding a migration

1. Write `m_<name>(root, ws)` in `scripts/migrate.py`: read files with `read()`, return `act(kind, path, new_text, note)` items only when something is still needed.
2. Add `(id, since, layer, fn)` to `MIGRATIONS` in the order it should apply.
3. Add the row above and a case to `tests/test_upgrade.sh` (fixture shaped like the old release; second run is a no-op).
4. A changed plugin template also gets its old sha256 in `scripts/asset-history.json`, so unedited copies upgrade automatically.

## Workspace

`migrate.py` in a workspace handles `plans/TEMPLATE.md`, `plans/active/*.md` and the workspace `AGENTS.md` only. Members are measured, never written: each one with stale assets, needed migrations or an older recorded version is printed as `member <name>: plugin <v>, <n> stale asset(s), <m> migration(s) — run /agent-harness:harness-upgrade <name>`.
