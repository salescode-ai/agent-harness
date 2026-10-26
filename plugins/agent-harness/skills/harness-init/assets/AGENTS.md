# AGENTS.md — <repo name>

> Read [INVARIANTS.md](INVARIANTS.md) first. This file is the map: it points to where things are, it does not explain them.

<one or two sentences: what this service does and who depends on it>. Structure: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Verification

- Done = `make check` passes (**harness-verify** before claiming done). Fast loop: `make check-fast`, `make test T=<path>`. All commands: `make help`.
- Run these targets, not raw tool commands.

## Working Principles

1. **Think before coding** — state assumptions; if two readings exist, ask instead of picking one silently.
2. **Simplicity first** — minimum code for the request; no speculative options, abstractions or error paths.
3. **Surgical changes** — every changed line traces to the request; mention unrelated issues, don't fix them.
4. **Goal-driven** — turn the task into a check (failing test, make target) and loop until it passes.
5. **Speak the domain** — name things with the terms in [GLOSSARY.md](GLOSSARY.md); if a concept is missing, flag it instead of inventing a synonym.

## Agent skills

Developers choose their own skill packs and plugins. Whatever is installed works inside this harness:

1. **Precedence:** `INVARIANTS.md` > this file and module `AGENTS.md` > repo skills in `.agents/skills/` > plugin skills > tool defaults. If a skill's default contradicts this file, follow this file.
2. **Artifacts** go where Work Artifacts says, not in a plugin's default folder.
3. **Proof** comes from the Verification make targets, not a plugin's own test command. **harness-verify** is the last step before "done", whatever process skill ran before it.
4. **One process per phase:** don't run two planning, test-first or review workflows over the same work in one session.
5. **Instructions** live in `AGENTS.md`. Setup or installer skills never write to `CLAUDE.md` and never copy plugin text into the repo.
6. **Pointers:** issue tracker: `docs/agents/issue-tracker.md` · triage labels: `docs/agents/triage-labels.md` · domain docs: `docs/agents/domain.md`.
7. **Team settings:** only the harness plugin is pinned in `.claude/settings.json`. Other plugins are personal (user scope); a plugin that adds hooks, MCP servers or permissions needs review before it is shared, and may never loosen the harness hooks or guards.

## Work Artifacts

- Specs/designs: `docs/specs/YYYY-MM-DD-<topic>.md` · Plans: `docs/plans/active/YYYY-MM-DD-<KEY>-<n>-<slug>.md` with a `Ticket:` line, branch `<KEY>-<n>-<slug>` (move to `docs/plans/done/` after a fresh PASS in the local `.harness/evidence/<plan file name>`)
- Decisions: `docs/adr/NNNN-<slug>.md`, indexed in [docs/DECISIONS.md](docs/DECISIONS.md) · Vocabulary: `GLOSSARY.md`
- Worktrees: `.worktrees/` · Session scratch: `.harness/` (both gitignored)
- Pack working notes: .harness/notes/

## Context loading

| Task | Read first |
|---|---|
| Any change | `INVARIANTS.md`, this file |
| New feature or design | `docs/ARCHITECTURE.md`, `GLOSSARY.md`, `docs/DECISIONS.md` |
| Writing or fixing tests | `docs/TESTING.md` |
| Dev environment or dependencies | `docs/SETUP.md` |
| Work in progress | `docs/plans/active/` |
| Issue tracker, labels, domain docs | `docs/agents/*.md` |
| <module task> | `<path>/AGENTS.md` |

## Agent Authorization

- **May, without asking:** <e.g. edit code and tests on a feature branch, run make targets, commit locally>
- **Must stop and ask:** <e.g. push, merge, change INVARIANTS.md, touch auth/billing/migrations, add a dependency>

## Modules

- `<path>/AGENTS.md` — <one line: why it has its own rules>

## Conventions

- Commits and branches: `CONTRIBUTING.md` (link it once it exists).
- `CLAUDE.md` holds only `@`-references. Any skill or installer that wants to add instructions writes to this file instead.

## Cadence

quick audit: every 30 days · full audit: every 90 days or after an incident · garden: every 7 days

## Footguns

- **<name>** — <what goes wrong, in one line>. <what to do instead>. See `docs/adr/NNNN-slug.md`.
