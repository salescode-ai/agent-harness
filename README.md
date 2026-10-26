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

**Updating:** `claude plugin update agent-harness@agent-harness`, then re-run `/agent-harness:harness-init` in each repo: it refreshes the scripts it copied there (unmodified copies only; local edits are reported, never overwritten). The session hook says when a repo's copies are older than the plugin.

## Commands you run

| Command | Use it |
|---|---|
| `/agent-harness:harness-init` | In a repo: scan, show the layout, then set up the harness one layer at a time |
| `/agent-harness:harness-audit` | Read-only: measure the level, score each layer, list fixes |
| `/agent-harness:harness-workspace` | In a folder of sibling repos: write workspace-level files only |

## The five layers

1. **Guides:** `AGENTS.md`, `INVARIANTS.md`, a `CLAUDE.md` shim, `GLOSSARY.md`.
2. **Sensors:** checks that catch mistakes (lint, tests, project sensors proven with a fixture).
3. **Context & State:** what loads automatically, plans, session state, size budgets.
4. **Tool & Permission:** the command surface (`make check`, `check-fast`, `setup`, `seed`, ...), guards and permission rules.
5. **Observability & Lifecycle:** audit log, cadence, session warnings when the audit is stale.

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

- `HARNESS_STOP_GATE=0`: turn off the stop gate for a session.
- `HARNESS_GUARD=0`: turn off the command and file guards for a session (not recommended).
- `HARNESS_SHARED_SERVICES=1`: `make setup` shares local services instead of giving the checkout its own compose project (and each linked worktree its own free ports; the main checkout keeps the `.env.example` ports).
- `HARNESS_ALLOW_SEED=1`: let `seed` and `reset` run when `scripts/harness/local-guard.sh` is missing, **and** override its refusal of a non-local database target (it prints a warning). Use only when you are sure.

## Self-test

```bash
bash tests/run.sh
```
