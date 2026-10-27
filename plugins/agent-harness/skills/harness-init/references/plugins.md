# Skills and Plugins Alongside the Harness

The harness holds the **facts** (rules, commands, paths, vocabulary). Skill packs and plugins bring **process** (how to plan,
test, debug, review). Which packs a developer uses is their choice; the harness never names or requires one. What the harness
does define is how any pack must behave inside the repo — that is the `## Agent skills` section of `AGENTS.md`.

## Rules every skill or plugin follows

| Rule | Why | Where it is enforced |
|---|---|---|
| `INVARIANTS.md` and `AGENTS.md` outrank any skill | Packs ship generic defaults; the repo knows its own constraints | `AGENTS.md` precedence line; reviewer agents |
| Save specs, plans, decisions and working notes where Work Artifacts says | One place to find work; ADR index stays complete | `AGENTS.md` Work Artifacts; `harness-garden` |
| Prove work with the resolved commands (`bash scripts/harness/cmd.sh . check`) | Every pack agrees on what "done" means | `AGENTS.md` Verification; stop-gate hook; `harness-verify` |
| `harness-verify` runs last before "done" | Independent reviewers, whatever process came first | `AGENTS.md`; skill description |
| One process skill per phase | Two planning or TDD workflows over the same work waste tokens and conflict | `AGENTS.md` |
| Never write to `CLAUDE.md`; never copy plugin text into the repo | `CLAUDE.md` is a pointer; copied text goes stale and duplicates rules | file-guard hook; `make harness-lint` |
| Never loosen hooks, guards, permissions or checks | The harness's guarantees must hold for every pack | guard hooks; `INVARIANTS.md` Harness Integrity |
| Parallel implementers work in their own worktrees under `.worktrees/`; a branch whose implementer stopped red is not merged | Each slice proves itself before it joins the integration branch; harness-verify then runs on the integration branch | `AGENTS.md` Agent skills rule 8; SubagentStop marks the red branch, the Bash guard refuses to merge it |

## Choosing scope

- **Project scope** (`.claude/settings.json`, committed): only `agent-harness`. Everyone gets the same guards and gates.
- **User scope** (`~/.claude/settings.json`): any skill pack a developer prefers. It applies to them only.
- **Local scope** (`.claude/settings.local.json`, gitignored): experiments in one repo.

## Before sharing a plugin with the team

1. Read its source: every `SKILL.md`, agent, hook script and MCP server definition. Look for remote code fetched at runtime and hidden Unicode.
2. Check what it adds to every session: `claude plugin details <name>` (always-on tokens). A pack that costs thousands of tokens per turn crowds out the task.
3. List its hooks and MCP servers. Anything that runs commands, opens network connections or changes permissions needs a reviewer.
4. Check its default paths and commands against `AGENTS.md`. Each conflict gets one line in Work Artifacts or Verification — never an edit to the plugin.
5. Try it on one repo for a week before adding it to any shared settings.

## Guidance a pack pasted into `CLAUDE.md`

`CLAUDE.md` stays a shim. During init, pasted pack guidance (`scan.json` → `pasted_guidance`) moves to `AGENTS.md` → Working Principles, duplicates removed. Pack scratch folders (`pack_folders`) get `.gitignore` entries and a Work Artifacts line.

## When a pack's default conflicts with the repo

Do not fork or edit the pack. Add or sharpen one line in `AGENTS.md` (Work Artifacts, Verification, or Agent skills).
Agents read `AGENTS.md` before any skill, and most packs explicitly defer to project instructions. If a pack ignores the
repo's instructions after that, record it with `harness-learn` and stop using it in this repo.

## Tools without plugins (Codex, Cursor, Copilot, Gemini)

- Harness skills: copy them into `.agents/skills/` with `install-local.sh` from the kit; most tools scan that folder.
- Subagents are a Claude Code feature. In other tools, `harness-verify` runs each agent's checklist itself in a separate pass, reading `agents/<name>.md`.
