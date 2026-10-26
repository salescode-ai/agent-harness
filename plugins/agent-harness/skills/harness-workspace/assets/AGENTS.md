# AGENTS.md — <workspace name> (multi-repo workspace)

> This folder is **not** a git repo. It holds checkouts of several repos; each has its own harness. Workspace rules here cover
> work that spans repos. Inside a repo, that repo's `AGENTS.md` and `INVARIANTS.md` apply too — if they conflict with this
> file, the stricter rule wins; if that is unclear, stop and ask.

## Repos and what each owns

Every change goes into the repo that owns it. Never put code for one repo inside another, and never import across repos by path.

| Repo | Path | Owns | Its rules |
|---|---|---|---|
| backend-api | `backend-api/` | <REST endpoints, business rules, DB schema and migrations> | [backend-api/AGENTS.md](backend-api/AGENTS.md) |
| portal | `portal/` | <web portal UI> | [portal/AGENTS.md](portal/AGENTS.md) |
| app | `app/` | <mobile app UI> | [app/AGENTS.md](app/AGENTS.md) |

Before editing files in a repo, read that repo's `AGENTS.md` and `INVARIANTS.md` (Claude Code also loads its `CLAUDE.md` when you open files there).

## Verification

- Done = `make check` passes here (each changed repo's own gate; **harness-verify** in workspace mode before claiming done). Fast loop: `make check-fast`, `make test R=<repo> T=<path>`. All commands: `make help`.
- Run these targets, not raw tool commands.
- A plan is done only after harness-verify recorded a fresh PASS (`scripts/harness/plan-check.sh fresh`).

## Cross-repo rules

1. **Contract first.** When an API changes, change and test the provider repo first; clients follow. Merge in `mergeOrder` from `harness-workspace.json`.
2. **Stay compatible.** API changes are additive (new fields optional, nothing removed or renamed) until every client repo has shipped against the new contract; removals are a separate, later change.
3. **One branch name** across the repos a feature touches (`make branch B=<name> R="<repo> <repo>"`); don't branch repos the feature doesn't touch.
4. **One commit history and PR per repo,** each carrying the same issue key and linking its sibling PRs.
5. **Shared contracts** (DTO fields, enums, error codes, route paths) must match across repos; the cross-repo reviewer checks this.
6. **No workspace files in repos.** This folder's files (`AGENTS.md`, `Makefile`, `plans/`, `.harness/`) never get copied or committed into a repo.

## Work Artifacts

- Cross-repo plans: `plans/active/YYYY-MM-DD-<KEY>-<n>-<slug>.md` with `Ticket:` (default: `issueKey` in `harness-workspace.json`; template `plans/TEMPLATE.md`; move to `plans/done/` when shipped). This folder is not versioned, so each PR description carries its repo's part of the plan.
- Decisions: an ADR in the repo that owns the decision (for a contract, the provider repo), linked from the other repos' PRs.
- Repo-only work (specs, plans, ADRs inside one repo): follow that repo's own Work Artifacts.

## Agent skills

Same rules as each repo's `AGENTS.md` → Agent skills: this file and repo `INVARIANTS.md`/`AGENTS.md` outrank any skill; artifacts go where Work Artifacts says; proof comes from the make targets; `harness-verify` runs last; nothing is written into `CLAUDE.md`.

## Creating a repo's harness

A request such as "create harness for <repo>" is answered with the exact command for the developer to run here: `/agent-harness:harness-init <repo>` (no interview: `/agent-harness:harness-init <repo> one-shot`). It works inside that repo only; never set up a repo's harness from the workspace by hand.

## Agent Authorization

- **May, without asking:** edit code and tests on feature branches in the repos the task names; run make targets; commit locally in each repo.
- **Must stop and ask:** push or merge in any repo; touch a repo the task did not name; break or remove a field in a shared contract; anything a repo's own Agent Authorization lists.
