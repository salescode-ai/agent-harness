# Sensor catalog

Candidate sensors per stack. Propose one only when the scan shows the evidence. Ask the developer about each. Tool order: (1) rule in the existing linter, (2) architecture-test library, (3) plain test in the repo's suite, (4) script in `scripts/harness/sensors/`. A new dev dependency needs a yes. Every sensor goes through `sensor-proof.sh` before it is wired in.

## Java / Spring

| Candidate | Evidence needed | Preferred tool |
|---|---|---|
| Controllers must not bypass the service layer (no repository calls from `@RestController`) | `controller/`, `service/`, `repository/` packages | ArchUnit test if present, otherwise a JUnit test using ArchUnit (propose it) |
| Write methods in services carry `@Transactional` | JPA or JDBC repositories, `@Service` classes | ArchUnit test |
| Flyway/Liquibase migration naming and no edits to applied migrations | `db/migration/` or `changelog` files | script: filename regex plus git diff on existing files |
| OpenAPI spec matches the routes | `openapi.yaml` and controller mappings | the repo's contract test, else script |

## React / TypeScript

| Candidate | Evidence needed | Preferred tool |
|---|---|---|
| No direct `fetch`/`axios` outside the API module | `src/api/` or `services/` directory, `fetch(` calls | ESLint `no-restricted-globals` / `no-restricted-imports` |
| No imports across feature boundaries | `src/features/*` layout | ESLint `no-restricted-paths` or dependency-cruiser if present |
| No `any` in exported types | `tsconfig.json` with `strict` | ESLint `@typescript-eslint/no-explicit-any` |

## Node

| Candidate | Evidence needed | Preferred tool |
|---|---|---|
| Layering: routes do not import the data layer | `routes/`, `db/` directories | ESLint `no-restricted-imports` |
| Lockfile committed and in sync | `package.json` plus lockfile | script: `npm ci --dry-run` or the package manager's frozen check |
| No `process.env` reads outside the config module | `config/` module | ESLint `no-process-env` with an override for config |

## Python

| Candidate | Evidence needed | Preferred tool |
|---|---|---|
| Import-layer rules (domain does not import web or db) | package layout with `domain/`, `api/`, `db/` | import-linter if present, else a test walking `ast` |
| No bare `except:` or `print` in library code | ruff or flake8 config | the existing ruff/flake8 rule |
| Migration naming and one head only | Alembic or Django migrations | script or the framework's own check command |

## Go

| Candidate | Evidence needed | Preferred tool |
|---|---|---|
| Package layering (handlers do not import storage) | `internal/` layout | a `go test` that lists imports with `go list -deps`, or depguard in golangci-lint if present |
| No `fmt.Print*` in non-main packages | golangci-lint config | forbidigo rule in golangci-lint |
| Errors are not ignored | golangci-lint config | errcheck (already in golangci-lint) |

## Any stack

| Candidate | Evidence needed | Preferred tool |
|---|---|---|
| No production data in seeds or fixtures | `db/seeds`, `seed.sql`, `fixtures/` | `scripts/harness/sensors/no-prod-data.sh` (shipped) |
| No secrets in git | `.env*` patterns, key-like strings | the secret scanner already in use, else a pre-commit scanner (propose it) |
| Docs mention only commands that exist | `AGENTS.md` command list, `Makefile` | `harness-lint` (shipped) |
