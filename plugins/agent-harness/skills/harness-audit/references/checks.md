# Audit checklists

Status per item: ✅ pass (1) · ⚠️ partial (0.5) · ❌ fail (0). Cite `file:line` or the command output for every status. Budgets come from `INVARIANTS.md` `## Context Budget` / `## File Size Budget` when present, else the harness defaults.

## The 10 health questions (`quick` and `full`)

1. **Integrity.** Do the file paths, commands and internal links in `AGENTS.md`, `INVARIANTS.md` and every `SKILL.md` still resolve? List any that don't.
2. **Constraint propagation.** Without re-reading the files, name the top 3 hard constraints from `INVARIANTS.md`. If you can't, or your list is much shorter than the file, the runtime may be dropping invariants.
3. **Sensors.** Does the check command pass? (`level.py` already ran it with `--run-checks`; read `sensors.missing`.) If not, what fails? Has the gate been proven red (`gate never proven red` in `sensors.missing` means no: report its reason; a `HARNESS_TEST_*` ending in `; :` keeps the gate green on failing tests)?
4. **Coverage gaps.** Are there new modules with security-sensitive code, API boundaries or complex logic and no module `AGENTS.md` or footgun?
5. **Enforcement gaps.** Can any invariant marked `not yet enforced` or `human review` now be automated (a sensor, lint rule or test)?
6. **Footgun freshness.** Is each footgun still a live risk, traceable to a concrete pattern in source? Flag aspirational ones.
7. **Token budget.** The auto-loaded set (`CLAUDE.md` + root `AGENTS.md` + `INVARIANTS.md`) is `tokens` in the `level.py` JSON (UTF-8 bytes / 4, the same number `harness-lint` prints): ≤ 3,000 pass, ≤ 5,000 partial, above fail.
8. **File size discipline.** Root `AGENTS.md` ≤ 100 lines, module `AGENTS.md` ≤ 80, `SKILL.md` ≤ 120. Flag a file only if it is over budget **and** does not point to detail elsewhere.
9. **Content accuracy.** Versions, dependencies, commands, env var names, paths and endpoints in the harness files match their source files (`.harness/scan.json` is the evidence; refresh it if `head` differs).
10. **Claude Code integration.** Every `.agents/skills/<name>` has a working `.claude/skills/<name>` symlink (a plain text file counts as rot); `CLAUDE.md` is a shim; no redundant `.claude/commands/` shims. N/A when there is no `CLAUDE.md` and no `.claude/`.

Recommend `full` when more than 2 fail.

## The 14-item completeness score (`full`)

Score = points ÷ 14 × 100.

| # | Layer | Item |
|---|---|---|
| 1 | guides | Root `AGENTS.md`: overview, Agent Authorization, footguns, link to `INVARIANTS.md` at the top |
| 2 | guides | `INVARIANTS.md`: specific, measurable rules, each with Severity and `Enforced by:` |
| 3 | guides | Module `AGENTS.md` for high-risk folders |
| 4 | guides | Repo skills (optional): routed and symlinked, or none needed |
| 5 | guides | `README.md` points to the harness entry point |
| 6 | sensors | `test` runs and passes |
| 7 | sensors | `lint` runs and passes |
| 8 | sensors | `check` combines all validation |
| 9 | sensors | Coverage target stated in `INVARIANTS.md` |
| 10 | context | Architecture documented (diagram, component roles) |
| 11 | context | Decision records exist for major choices |
| 12 | tools | Setup lets a new engineer run the repo from scratch (`setup-proof.sh` OK) |
| 13 | context | Known footguns documented in `AGENTS.md` |
| 14 | observability | Auto-loaded total within budget |

Bands: **80–100** healthy · **60–79** gaps to schedule · **below 60** address before the next major agent task · **below 40** prioritise remediation.

## Content-quality pass (`full`)

For each harness file: is every rule specific and traceable to a failure, incident or hard constraint? Generic advice ("write clean code"), duplicated rules (one owner per fact) and stale `[verify]` markers are findings.
