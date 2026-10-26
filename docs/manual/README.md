# agent-harness 2.0.0 — Manual

agent-harness is a Claude Code plugin that sets up, checks and maintains a **repository harness** for AI coding agents. The harness is the set of files, commands and hooks in your repo that tell an agent what the rules are, how to prove its work, and what it may not touch.

This manual is for:

- **Developers** adopting the plugin on a repo. You know git and your stack; you don't need to know this plugin yet.
- **Team leads** deciding how far to take it (the target level), what to commit for the whole team, and what to review.

## Contents

| File | Read it when |
|---|---|
| [01-concepts.md](01-concepts.md) | You want to know what a harness is, the five control layers, and how the maturity level is measured |
| [02-file-reference.md](02-file-reference.md) | You want to know what a file in your repo does, who writes it, who reads it, and whether you may edit it |
| [03-user-guide.md](03-user-guide.md) | You are installing the plugin, running setup, using the everyday skills, or something is blocking you |
| [04-workspace.md](04-workspace.md) | One feature spans several repos (backend, portal, app) checked out side by side |

**Reading order.** Team leads: 01 → 03 (install, init, audit) → 02 as needed. Developers: the quick start below → 03 → 02 when a file surprises you. Read 04 only if you work across repos.

## Quick start (5 minutes)

1. **Install the plugin** in the repo (project scope, so the whole team gets the same hooks):

   ```bash
   claude plugin marketplace add <your-org>/agent-harness
   claude plugin install agent-harness@agent-harness --scope project
   ```

2. **Run setup** from a Claude Code session in the repo root:

   ```text
   /agent-harness:harness-init
   ```

   It scans the repo without asking anything, shows you a file tree of what it will write, and waits for one "yes". Then it asks a few questions per layer, each with a default (reply `defaults` to accept them all). Use `/agent-harness:harness-init one-shot` to skip the questions entirely.

3. **Wire this checkout's git hooks** once setup is finished (the agent's guard allows only `git config core.hooksPath .githooks`, so the agent may also do this step):

   ```bash
   make setup
   ```

4. **Work as usual.** From now on:
   - every session starts with a short orientation (branch, active plan, warnings);
   - dangerous commands (force-push, `git reset --hard`, `--no-verify`, …) are blocked;
   - when the agent tries to stop with changed code, `check-fast` runs and blocks the stop if it fails;
   - before saying "done", the agent runs the `harness-verify` skill (the gate plus independent reviewers).

5. **Check the result** any time:

   ```text
   /agent-harness:harness-audit
   ```

   It reports a measured level such as `Level: Functional · target: Robust · blocked by: …` and a ranked list of fixes.

## The three commands you type

| Command | What it does |
|---|---|
| `/agent-harness:harness-init` | Set up, resume, or upgrade the harness in this repo. Argument `one-shot` skips the interview. |
| `/agent-harness:harness-audit` | Read-only audit. `quick` (default, monthly) or `full` (quarterly or after an incident). |
| `/agent-harness:harness-workspace` | In a folder of sibling repos: write workspace-level files only. |

Everything else (verify, session, learn, garden, glossary, and the reviewer agents) is used by the agent itself or on request. See [03-user-guide.md](03-user-guide.md).

## Source of truth

This manual describes the plugin in `plugins/agent-harness/`. When the manual and the code disagree, the code wins: the skills (`skills/*/SKILL.md`), agents (`agents/*.md`), hook scripts (`scripts/`) and templates (`skills/harness-init/assets/`). The design rationale is in `docs/specs/2026-10-26-harness-v2-design.md`.
