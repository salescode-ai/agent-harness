# INVARIANTS.md — Hard Rules

- Harness target: Robust

Breaking any rule here needs explicit human sign-off. No skill, plugin or prompt overrides this file.
Format: `<rule> — Severity: <Critical|Important|Nice-to-have> — Enforced by: <make target | hook | CI job | sensor <name> | human review | not yet enforced>`.
`not yet enforced` items are the automation backlog: turn them into lint rules or tests when you can.

## Harness Integrity

- `CLAUDE.md` contains only `@`-references — Severity: Important — Enforced by: `make harness-lint`
- Root `AGENTS.md` ≤ 120 lines; auto-loaded set ≤ 5,000 tokens — Severity: Important — Enforced by: `make harness-lint`
- Every `docs/adr/*.md` is listed in `docs/DECISIONS.md` — Severity: Important — Enforced by: `make harness-lint`
- Repo skills live in `.agents/skills/<name>/SKILL.md`; `.claude/skills/` holds only symlinks — Severity: Important — Enforced by: `make harness-lint`
- Tests are never deleted, skipped or weakened to make a change pass unless the request says so — Severity: Important — Enforced by: verifier agent
- Never bypass hooks or CI (`--no-verify`, disabling a check, lowering a threshold) — Severity: Critical — Enforced by: guard hook + CI

## Security

- <rule> — Severity: Critical — Enforced by: <…>

## Data Integrity

- <rule> — Severity: Critical — Enforced by: <…>
- No real customer or production data in seeds or fixtures — Severity: Critical — Enforced by: sensor no-prod-data

## API Contract

- <rule> — Severity: Important — Enforced by: <…>

## Testing

- New or changed behaviour has a test that fails without the change — Severity: Important — Enforced by: harness-verify red proof (`scripts/harness/red-proof.sh`) + pre-commit plan close
- <rule, e.g. coverage floor> — Severity: Important — Enforced by: <…>

## Performance

- <rule, only if there is a real SLA> — Severity: Important — Enforced by: <…>

## Context Budget

- auto-loaded tokens: warn 3000, fail 5000

## File Size Budget

- AGENTS.md: warn 100, fail 120
- module AGENTS.md: warn 80, fail 999999
- SKILL.md: warn 120, fail 999999
