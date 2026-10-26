# harness.mk — verification targets agents rely on.
# Include from the root Makefile:   include harness.mk
# Then point the HARNESS_* variables at this repo's real commands (keep them quiet on success).
# Agents: run only make targets. No raw tool commands for build, test or lint.

HARNESS_LINT      ?= @echo "lint: not configured" && false
HARNESS_TYPECHECK ?= @true
HARNESS_TEST_ALL  ?= @echo "test: not configured" && false
HARNESS_TEST_ONE  ?= @echo "test T=: not configured" && false
HARNESS_SMOKE     ?= @echo "smoke: no runnable surface"
# Tests for changed files only (receives the file list). Leave empty to skip tests in check-fast.
HARNESS_TEST_CHANGED ?=
# Files changed vs the main branch (used by check-fast)
HARNESS_BASE      ?= origin/main
CHANGED            = $(shell git diff --name-only --diff-filter=ACMR $(HARNESS_BASE)...HEAD 2>/dev/null; git diff --name-only --diff-filter=ACMR HEAD 2>/dev/null)

# Changed files under a dir with given extensions, relative to that dir (for tools with legacy debt):
#   UI_CHANGED = $(call harness_changed,ui/,ts tsx)
harness_changed = $(patsubst $(1)%,%,$(filter $(foreach e,$(2),$(1)%.$(e)),$(CHANGED)))

# Optional single-test selector: make test T=tests/test_auth.py
T ?=

.PHONY: help check check-fast lint typecheck test smoke harness-lint

help: ## List targets (delete this one if your Makefile already defines help)
	@echo "Agents: run only these make targets."
	@grep -hE '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS=":.*## "} {printf "  %-14s %s\n", $$1, $$2}'


check: lint typecheck test harness-lint ## Completion gate: lint + typecheck + all tests + harness lint
	@echo "check: OK"

check-fast: lint typecheck ## Quick gate (< 60 s): lint + typecheck + tests for changed files if configured
ifneq ($(strip $(HARNESS_TEST_CHANGED)),)
	$(HARNESS_TEST_CHANGED) $(CHANGED)
endif
	@echo "check-fast: OK"

lint: ## Lint
	$(HARNESS_LINT)

typecheck: ## Type check
	$(HARNESS_TYPECHECK)

test: ## All tests, or one file/test with T=<path>
ifeq ($(strip $(T)),)
	$(HARNESS_TEST_ALL)
else
	$(HARNESS_TEST_ONE) $(T)
endif

smoke: ## Start the app and hit one real path
	$(HARNESS_SMOKE)

harness-lint: ## Structural checks on the harness files themselves
	@bash scripts/harness/lint.sh

# Example wiring (Python):
#   HARNESS_LINT      = ruff check -q .
#   HARNESS_TYPECHECK = mypy --no-error-summary src
#   HARNESS_TEST_ALL  = pytest -q --cov=src
#   HARNESS_TEST_ONE  = pytest -q
#   HARNESS_TEST_CHANGED = pytest -q --testmon   # or a script mapping changed files to tests
# Example wiring (Node/TypeScript):
#   HARNESS_LINT      = npx eslint --quiet .
#   HARNESS_TYPECHECK = npx tsc --noEmit
#   HARNESS_TEST_ALL  = npx vitest run --silent
#   HARNESS_TEST_ONE  = npx vitest run
#   HARNESS_TEST_CHANGED = npx vitest related --run
