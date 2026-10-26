# Testing

Commands live in the Makefile (`make test`, `make test T=<path>`, `make check`). Coverage and other hard floors live in INVARIANTS.md.

## Layout
<!-- where unit, integration and e2e tests live; naming convention -->

## What must have tests
<!-- critical paths and why -->

## Fixtures and mocks
<!-- what to mock, what never to mock (e.g. the database in integration tests) -->

## Proving a change
A test proves a change only if it fails without the change. Prefer a failing test first; never weaken an existing one to pass.
