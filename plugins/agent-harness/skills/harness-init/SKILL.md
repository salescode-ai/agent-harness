---
name: harness-init
description: Set up or migrate the agent harness in a repository — AGENTS.md map, INVARIANTS.md, CLAUDE.md shim, GLOSSARY.md, docs/ system of record, Makefile verification targets, harness lint, CI, and rules for any skill packs developers use. Use once per repo, or to bring an older setup up to date.
disable-model-invocation: true
---

# Harness Init

Build the harness in the order that keeps every fact sourced from the step that owns it. Work **section by section**: show the evidence (`file:line`), show what you will write, wait for a yes. Arguments: `one-shot` skips the pauses and stamps every new file with `<!-- generated in one pass: verify before trusting -->`.

**While this skill runs, it is the process.** Do not invoke planning, test-first, review or interview skills from other plugins.

## Ground rules

- **Evidence or a marker.** Every identifier written into a harness file (path, env var, target, route, class, table) needs a `file:line` you observed. Otherwise write `[verify]`. READMEs and wikis are claims, not evidence.
- **Ask, don't invent.** Code cannot tell you: who may merge, what needs a human, why a decision was made, what broke in production, what a domain term means. Ask the developer; write `TODO` if they don't know.
- **One owner per fact.** See the ownership table in `references/layout.md`. Everything else links.
- **Ratchet, not wishlist.** A rule earns its place by tracing to a real failure, incident, or hard external constraint. No generic advice ("write clean code").
- **Extend, don't clobber.** Existing files are read first and extended; content in the wrong place is moved, then the original deleted only after the developer confirms nothing is lost.

## Steps

1. **Probe (baseline).** Run the probe in `references/probe.md`. Keep the answer in the conversation.
2. **Map the repo.** Dispatch the `repo-cartographer` agent (`agent-harness:repo-cartographer` when installed as a plugin) (or follow its procedure yourself if your tool has no subagents). Also run `bash <this skill>/scripts/scan.sh` for a quick artifact list.
3. **Detect tools.** Ask once which agent tools the team uses (Claude Code / Codex / Cursor / Copilot). Don't ask which skill packs they use — that is each developer's choice; note any pack residue in the map (pasted guidelines in `CLAUDE.md`, plugin folders under `docs/`) so step 5.8 can route it.
4. **Plan.** Present a table: file · create / extend / move · source of content · questions for the developer. Wait for approval.
5. **Execute in this order** (templates in `assets/`, details in `references/layout.md`):
   1. `Makefile` targets — copy `assets/harness.mk` to the repo root and `assets/lint.sh` to `scripts/harness/lint.sh`, include `harness.mk` and wire its `HARNESS_*` variables to the real commands from the map: `check`, `check-fast`, `test` (with `T=`), `smoke` if there is a runnable surface, `harness-lint`.
      **Green baseline first:** run every candidate command on the untouched repo before wiring it. The harness must land with `make check-fast` green on today's code — otherwise the stop gate blocks every session on debt nobody caused. A tool that already fails (e.g. 56 legacy lint errors) is wired in **changed-files mode** (`$(call harness_changed,<dir>/,<ext…>)`, see `references/layout.md`) and recorded as an invariant `whole-repo <tool> clean — Enforced by: not yet enforced (<n> errors on main, <date>)`. Never fix legacy errors or loosen a tool's config as part of init. Tools the repo doesn't have, or that can't run here (Docker, a missing JDK), become `[not yet enforced]` invariants or are noted for the developer — never stubs that pretend to pass.
   2. `INVARIANTS.md` — Harness Integrity block verbatim, then one category at a time from evidence and developer answers, each rule with `Enforced by:`.
   3. Root `AGENTS.md` — map under 100 lines: overview, Verification, Working Principles, Skills and plugins, Work Artifacts, Agent Authorization (ask), Module map, Footguns (ask for incidents).
   4. `CLAUDE.md` shim (Claude Code only) — `@AGENTS.md` and `@INVARIANTS.md`, nothing else. Migrate any real content out first, moving it by script rather than retyping, and check afterwards that every original line exists somewhere. An `@import` in the old file (e.g. a style or theme spec) moves to the module shim of the folder it governs, so it still auto-loads there.
   5. Module `AGENTS.md` — only where a module is high-risk, has its own toolchain, or has ≥10 lines of genuinely local rules. For Claude Code, add `<module>/CLAUDE.md` containing `@AGENTS.md` (plus any `@import` moved from the root) — Claude Code loads a folder's `CLAUDE.md` when it opens files there, but does not read `AGENTS.md` on its own.
   6. `docs/` — ARCHITECTURE.md (from the map), TESTING.md, DECISIONS.md index + `docs/adr/` (decisions come from developer dialogue only: mine `git log` for candidates, ask why, transcribe), `docs/plans/` with the plan template, `docs/agents/` (issue tracker + domain).
   7. `GLOSSARY.md` — offer to seed 5–10 core terms through a short dialogue; definitions come from the developer, never from code alone. Otherwise create it with the header only.
   8. Skills and plugins — fill the "Skills and plugins" section from the template and set Work Artifacts paths. If the repo already has a plugin's folders in use (e.g. specs or plans under a plugin-named directory), keep them and point Work Artifacts at them rather than moving history. Rules and vetting: `references/plugins.md`. Pin only `agent-harness` in `.claude/settings.json` (`assets/claude-settings.json`). Claude Code protects `.claude/settings.json`; if the write is refused, don't work around it — show the developer the file content to add themselves.
   9. Mechanical sensors — copy `assets/harness.yml` → `.github/workflows/` (or translate it to the repo's CI); append `assets/gitignore.append` to `.gitignore`.
6. **Validate.** Run `make harness-lint` and `make check`. Dispatch `harness-auditor`. Fix RED items.
7. **Probe again.** Same prompt as step 1, fresh session if possible. Report the difference in the conversation — do not save it to a file (a model grading its own setup is not a measurement).

## Done when

`make harness-lint` and `make check` pass, `harness-auditor` is GREEN or AMBER with only accepted warnings, and the second probe reads `AGENTS.md` first, names the Verification command, and stops at the escalation triggers.
