# agent-harness

A repository harness for AI coding agents, packaged as a Claude Code plugin marketplace. It gives a repo the facts and rules every agent follows (`AGENTS.md`, `INVARIANTS.md`), the commands to check its work, and the hooks that enforce them. It works with whatever skill packs a team already uses.

## Install

**Claude Code** (push this folder to a repo your team can read):

```bash
claude plugin marketplace add salescode-ai/agent-harness
claude plugin install agent-harness@agent-harness --scope project
```

**Codex, Cursor, Copilot, Gemini:**

```bash
bash install-local.sh /path/to/repo
```

This copies skills to `.agents/skills/`, agent checklists to `.agents/agents/`, the harness scripts to `scripts/harness/` and the git hooks to `.githooks/`. Existing files are skipped. It provides only scripts, skills, agent checklists and git hooks; run `harness-init` (or fill in the templates yourself) to reach Experimental. Agent hooks are Claude Code only.

**Headless (`claude -p`, CI):** the skills read files in the plugin folder, outside the repo, and a non-interactive run cannot ask for that. Add `--add-dir ~/.claude/plugins/cache/agent-harness` (or, for a local checkout, `--plugin-dir <path>/plugins/agent-harness --add-dir <same path>`) and `--permission-mode auto`, e.g. `claude -p "/agent-harness:harness-init one-shot" --add-dir ~/.claude/plugins/cache/agent-harness --permission-mode auto`. Details: `docs/manual/03-user-guide.md` → Headless and CI runs.

**Updating:** `claude plugin update agent-harness@agent-harness`, then run `/agent-harness:harness-upgrade` in each repo: it refreshes the scripts it copied there (unmodified copies only; local edits are reported, never overwritten), applies the versioned migrations (safe ones automatically, edits to your files as one diff for a single yes) and records the version in `scripts/harness/assets.json`. The session hook says when a repo's copies are older than the plugin.

## Commands you run

| Command | Use it |
|---|---|
| `/agent-harness:harness-init` | In a repo: scan, show the layout, then set up the harness one layer at a time |
| `/agent-harness:harness-audit` | Read-only: measure the level, score each layer, list fixes |
| `/agent-harness:harness-upgrade` | After a plugin update: refresh copied scripts, migrate harness files to the new version, verify, record the version |
| `/agent-harness:harness-improve` | Strengthen a thin harness from evidence (git history, risk paths, unenforced rules): one area per round, you accept or skip each suggestion. init and audit offer it at the end |
| `/agent-harness:harness-workspace` | In a folder of sibling repos: write workspace-level files only |

After init, check the setup step by step (audit, commands, git hooks, a deliberate red test, sensor and setup proofs): `docs/manual/03-user-guide.md` → Check your setup after init.

## Without the plugin installed

A harness has two halves:

1. **Committed repo files: work for everyone and any tool.** The guides (`AGENTS.md`, `INVARIANTS.md`, `CLAUDE.md`, `GLOSSARY.md`, `docs/`), the `Makefile` + `harness.mk` + `scripts/harness/` targets (`make check`, `check-fast`, `test`, `setup`, `seed`/`reset` behind `local-guard.sh`, `harness-lint`, the sensor proofs), the `.githooks/` once `make setup` has run in that clone, and CI if you opted in. Anyone can run `make check` without Claude Code.
2. **Plugin only (Claude Code).** The hooks (stop gate, Bash and file guards, session orientation), the skills and the reviewer agents. They are not copied into the repo.

**Team rollout.** Commit `.claude/settings.json` with `extraKnownMarketplaces.agent-harness` and `enabledPlugins: {"agent-harness@agent-harness": true}`: every teammate's Claude Code then offers the plugin when they trust the folder. `harness-init` asks before writing it; one-shot leaves it as a TODO; `harness-improve` lists "team rollout settings missing" as a gap until it is there. For other tools, `install-local.sh` copies the skills to `.agents/skills/`; there are no agent hooks there, so enforcement comes from the git hooks and CI.

## What a harness is

An agent is a model plus a harness. The model is the same for everyone; the harness is what your repo gives it: the facts, the rules, the commands that prove work is done, and the checks that stop it when it isn't. When an agent makes a mistake, fix the harness rather than the prompt, so the next session (and every teammate's agent) gets the fix too.

The harness is organised in five layers. Each one acts at a different moment: before the agent starts, while it works, or after it finishes.

### 1. Guides: what the agent reads before it acts

| File | What it holds |
|---|---|
| `AGENTS.md` | The map: what the repo does, how to verify work, which files to read for which task, where specs, plans and decisions go, what the agent may do alone and what needs a human, known traps (footguns). Under ~100 lines. |
| `INVARIANTS.md` | Hard rules, each with a severity (Critical, Important, Nice-to-have) and how it is enforced (`make` target, sensor, hook, CI, human review, or `not yet enforced`). Also the harness target level and size budgets. |
| `CLAUDE.md` | A two-line pointer (`@AGENTS.md`, `@INVARIANTS.md`) so Claude Code loads the guides. Nothing else goes here. |
| `<module>/AGENTS.md` | Local rules for risky or different modules (auth, payments, migrations, a separate toolchain). |
| `GLOSSARY.md` | One word per domain concept, so code, tests, tickets and specs agree. |
| `docs/` | `ARCHITECTURE.md`, `TESTING.md`, `SETUP.md`, decision records (`DECISIONS.md` + `adr/`), `plans/`, `specs/`, and `agents/` (issue tracker and domain notes other skill packs read). |

### 2. Sensors: checks that catch mistakes after the agent acts

| Piece | What it does |
|---|---|
| `make check` | The definition of done: lint + typecheck + all tests + harness lint. |
| `make check-fast` | The same on changed files only (under ~60 s), including the tests related to changed source files. |
| `scripts/harness/red-proof.sh` | Test-first, proven: harness-verify runs the change's tests in a scratch worktree with the change (green) and without it (must fail). A plan closes only when its evidence says `Red: proven` or `Red: n/a (<reason>)`. |
| `scripts/harness/sensors/` | Project-specific checks (architecture rules, "no production data in seeds", contract checks). Each is wired only after a proof run: clean code passes, a planted violation fails, and the planted fixture is kept so the sensor is re-proved on every lint. |
| `scripts/harness/lint.sh` | Structural checks on the harness itself: shim, budgets, broken links, rule format, commands that don't exist. |
| `.githooks/` | pre-commit runs `check-fast`, pre-push runs `check` (or added to your existing husky / lefthook / pre-commit). pre-commit also refuses to close a plan (moved to `plans/done/` or `Status: done`) unless `scripts/harness/plan-check.sh fresh` passes on its local evidence. |

### 3. Context & State: what the agent remembers and loads

| Piece | What it does |
|---|---|
| Context loading table (in `AGENTS.md`) | Task type → files to read, so the agent loads the right detail and nothing more. |
| `docs/plans/active/` | Long tasks as plans with a `Ticket:`, steps and a progress log, so work survives `/clear`, compaction and new sessions. harness-verify's evidence goes to the local `.harness/evidence/<plan file name>` (never committed) and is shared through the PR description and the tracker comment. |
| Size budgets | The auto-loaded guides stay small (≤ 3,000 tokens target) so they don't crowd out the task. |
| `.harness/` | Local, gitignored state: scan results, setup progress, last green check. |

### 4. Tool & Permission Boundaries: what the agent may run and touch

| Piece | What it does |
|---|---|
| `Makefile` + `harness.mk` (or `.agents/harness.json`) | The one command surface: `check`, `check-fast`, `test T=`, `setup`, `seed`, `reset`, `dev`, `dev-check`, `smoke`. Every hook, skill and teammate uses the same commands. |
| `make setup` | One command for a working dev environment on a fresh machine or any worktree: dependencies, services, migrations, synthetic test data, git hooks, then a smoke check once nothing is left for you to do (`HARNESS_SETUP_SMOKE = 0` keeps a server app's smoke out of setup; unset smoke reports `n/a`, not ✓). |
| `make dev-check` | With `HARNESS_HEALTH` set (a URL or command meaning "the app is up"): starts `make dev` in the background, waits until healthy, runs `RUN='<cmd>'` against it, and always stops it. `make dev-stop` stops a leftover one. |
| Guard hooks | Block force-push, `--no-verify`, `git reset --hard`, destructive deletes, and writes to `CLAUDE.md` and `.env`. Ask before `kubectl delete`, `terraform destroy`, `terraform apply -auto-approve`, `helm uninstall`, destructive SQL and any write to `INVARIANTS.md`. Once `dev-check` is wired, refuse a long-lived `make dev` (also behind `nohup`, `bash -c`, `VAR=`) and the run scripts listed in `HARNESS_DEV_BLOCK`. |
| Stop gate | Claude can't finish a turn while `check-fast` fails on its changes. When a subagent working in its own git worktree (a parallel implementer) stops with `check-fast` failing there, its branch is marked red and the Bash guard refuses to merge or cherry-pick it until a later stop there passes. Reviewers and explorers in the main checkout are never checked. |
| `scripts/harness/local-guard.sh` | `seed` and `reset` refuse anything that isn't a local database. |
| `.claude/settings.json` | Pins the plugin for the team and denies reading secret files. |

### 5. Observability & Lifecycle: keeping the harness true over time

| Piece | What it does |
|---|---|
| `/agent-harness:harness-audit` | Measures the level and a score per layer, lists what blocks the next level. Read-only. |
| `docs/harness/AUDIT-LOG.md` | One measured line per audit, so you can see the trend. |
| Cadence (in `AGENTS.md`) | Quick audit monthly, full audit quarterly or after an incident, garden weekly. The session start says when an audit is overdue or the repo's harness scripts are older than the plugin. |

## Improving your harness: what the team owns

Setup gets you to a working baseline. These are the parts only your team can supply, roughly in order of payoff:

1. **Answer the TODOs init leaves.** Agent Authorization (what the agent may do alone, what needs a human), the one-line repo overview, and domain terms in `GLOSSARY.md`. Code can't tell the agent these.
2. **Record footguns from real incidents.** Every time something broke in production or an agent made a costly mistake, add one line to `AGENTS.md` → Footguns with the file and the safe path. These are the highest-value lines in the harness.
3. **Turn "not yet enforced" rules into checks.** Each `not yet enforced` invariant is backlog. Move it up the ladder: a lint rule or test beats a hook, a hook beats a written rule. Use **harness-learn** after any repeated mistake; it picks the strongest fix and proves it.
4. **Pay down legacy debt deliberately.** Tools that failed on day one are wired in changed-files mode; the full-repo rule is recorded as debt. Shrink it over time, then switch the tool to whole-repo mode.
5. **Wire the tools that were skipped or declined.** If init couldn't run your tests or lint (missing credentials, no linter), wire them once they work, so the gate checks something real.
6. **Write decisions down.** When you choose one approach over another, add an ADR (`docs/adr/`) so agents stop re-arguing it.
7. **Raise the level.** Turn on git hooks (`make setup`), add CI running `make check`, add permission rules and CODEOWNERS for the harness files. The audit tells you exactly what blocks the next level.
8. **Keep it alive.** Run **harness-garden** weekly to fix drift (renamed paths, dead links, finished plans) and `/agent-harness:harness-audit` monthly. Prune rules that no longer apply; a harness that only grows becomes noise.

## Levels and target

The audit measures the level (`Experimental`, `Functional`, `Robust`, `Enterprise`); it cannot be declared. You set a target in `INVARIANTS.md` as `Harness target: <level>`, and setup and audit never go past it. Functional covers Guides and Sensors, Robust all five layers, Enterprise adds CI, CODEOWNERS and audit history.

## Where checks run

| Place | Default | Notes |
|---|---|---|
| Agent hooks (stop gate, guards) | on | Agents only; Claude Code |
| Git hooks: pre-commit runs `check-fast`, pre-push runs `check` | on | If a hook manager exists (husky, lefthook, pre-commit), add to its config. Otherwise use `.githooks/` with `core.hooksPath`, set by `make setup`. The session hook warns when the hooks are off. |
| CI workflow | opt-in | Generated only on a yes, after the explanation is shown. It is the only check nobody can skip; required for Enterprise. |

## Using a runner other than make

Register commands in `.agents/harness.json`. Hooks, the verifier, the audit and git hooks read it first and fall back to `make <target>`:

```json
{ "runner": "just",
  "commands": { "check": "just check", "check-fast": "just quick", "test": "just test {T}",
                "setup": "just bootstrap", "seed": "just seed", "reset": "just reset",
                "smoke": "just smoke", "dev": "just dev" } }
```

`AGENTS.md` -> Verification must show the same commands; `harness-lint` fails when they disagree.

## Settings

- `HARNESS_STOP_GATE=0`: turn off the stop gate (and the red-branch check for worktree subagents) for a session.
- `HARNESS_GUARD=0`: turn off the command and file guards for a session (not recommended).
- `HARNESS_SHARED_SERVICES=1`: `make setup` shares local services instead of giving the checkout its own compose project (and each linked worktree its own free ports; the main checkout keeps the `.env.example` ports).
- `HARNESS_ALLOW_UNVERIFIED_DONE=1`: let the pre-commit hook close a plan when this machine has no `.harness/evidence/` at all (it prints a notice). Stale or failing evidence still blocks.
- `HARNESS_ALLOW_SEED=1`: let `seed` and `reset` run when `scripts/harness/local-guard.sh` is missing, **and** override its refusal of a non-local database target (it prints a warning). Use only when you are sure.

## Self-test

```bash
bash tests/run.sh
```
