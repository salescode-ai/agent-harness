# INVARIANTS.md — Hard Rules

Breaking any rule here needs explicit human sign-off. No skill, plugin or prompt overrides this file.
Format: `<rule> — Enforced by: <make target | hook | CI job | human review | not yet enforced>`.
`not yet enforced` items are the automation backlog: turn them into lint rules or tests when you can.

## Harness Integrity

- `CLAUDE.md` contains only `@`-references — Enforced by: `make harness-lint`
- Root `AGENTS.md` ≤ 120 lines; auto-loaded set ≤ 5,000 tokens — Enforced by: `make harness-lint`
- Every `docs/adr/*.md` is listed in `docs/DECISIONS.md` — Enforced by: `make harness-lint`
- Repo skills live in `.agents/skills/<name>/SKILL.md`; `.claude/skills/` holds only symlinks — Enforced by: `make harness-lint`
- Tests are never deleted, skipped or weakened to make a change pass unless the request says so — Enforced by: verifier agent
- Never bypass hooks or CI (`--no-verify`, disabling a check, lowering a threshold) — Enforced by: guard hook + CI

## Security

- <rule> — Enforced by: <…>

## Data Integrity

- <rule> — Enforced by: <…>

## API Contract

- <rule> — Enforced by: <…>

## Testing

- <rule, e.g. coverage floor> — Enforced by: <…>

## Performance

- <rule, only if there is a real SLA> — Enforced by: <…>
