# agent-harness

A repository harness for AI coding agents, packaged as a Claude Code plugin marketplace.

- **Skills:** `harness-init`, `harness-workspace`, `harness-verify`, `harness-session`, `harness-learn`, `harness-garden`, `harness-glossary`
- **Agents:** `repo-cartographer`, `verifier`, `invariants-reviewer`, `scope-guard`, `cross-repo-reviewer`, `harness-auditor`
- **Hooks:** session orientation, command guard, file guard, stop gate (`make check-fast`)
- **Templates:** AGENTS.md, INVARIANTS.md, CLAUDE.md shim, GLOSSARY.md, docs/ (architecture, testing, ADRs, plans, agents config), harness.mk, harness lint, CI workflow

Works with any skill pack a developer chooses: packs bring process, the harness holds the facts and the rules every pack follows.

## Install (Claude Code)

Push this folder to a GitHub repo your team can read (e.g. `<your-org>/agent-harness`), then:

```bash
claude plugin marketplace add <your-org>/agent-harness
claude plugin install agent-harness@agent-harness --scope project
```

In a repo: `/agent-harness:harness-init`. In a multi-repo workspace folder: `/agent-harness:harness-workspace`.

## Install (Codex, Cursor, Copilot, Gemini)

```bash
bash install-local.sh /path/to/repo
```

Copies the skills to `.agents/skills/` and the agent checklists to `.agents/agents/`. Hooks are Claude Code only; CI runs the same gate.

## Settings

- `HARNESS_STOP_GATE=0` — turn off the stop gate for a session
- `HARNESS_GUARD=0` — turn off the command/file guards for a session (not recommended)
