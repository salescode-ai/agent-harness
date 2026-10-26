# Dev setup

`make setup` gets a working local environment from a fresh clone. It is safe to re-run and isolated per worktree.

## Dependency inventory

Every external thing the app needs. Resolved rows cite `file:line`; unresolved rows say where to read.

| Dependency | Kind | Version | Source/evidence | Local mode (service\|stub\|shared-env\|not needed) | Details from |
|---|---|---|---|---|---|
| <name> | <database \| queue \| cache \| API \| runtime> | <version> | <file:line> | <mode> | <doc, owner or env> |

## `make setup` steps

1. Check tool versions (runtime, package manager, container engine) and report what is missing.
2. Install dependencies with the repo's package manager.
3. Start local services for rows whose mode is `service`; wire stubs for `stub` rows.
4. Create `.env.local` from the example file (never commit it; never copy real secrets).
5. Run `make seed` for local data, then `make smoke` to prove the app runs.

`make seed` and `make reset` refuse non-local targets. Secrets are never fetched by the harness: ask the owner named in "Details from".
