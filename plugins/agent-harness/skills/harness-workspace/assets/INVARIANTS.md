# Invariants — <workspace name> (cross-repo)

Rules for work that spans repos. Each repo's own `INVARIANTS.md` still applies inside that repo.

## Invariants

- Change the contract first: the repo that owns an API changes and tests it before any client repo — Severity: Critical — Enforced by: cross-repo-reviewer (harness-verify)
- Merge in `mergeOrder` from `harness-workspace.json`: providers before their clients — Severity: Critical — Enforced by: review (PR links between sibling PRs)
- No breaking API change without a version: additive changes only until every client has shipped; removals are a separate later change — Severity: Critical — Enforced by: cross-repo-reviewer (harness-verify)
- Never write code for one repo inside another, and never import across repos by path — Severity: Important — Enforced by: review
- Use one branch name and one issue key across the repos a feature touches — Severity: Nice-to-have — Enforced by: make status
