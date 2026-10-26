# Agents: run only make targets listed here. No direct shell commands.
# harness.mk — verification targets agents rely on. Include from the root Makefile:   include harness.mk
# Point the HARNESS_* variables at this repo's real commands (keep them quiet on success).
# To keep a target your Makefile already defines, set HARNESS_DEFINE_<NAME>=0 before the include
# (NAME upper-case, - becomes _), e.g. HARNESS_DEFINE_HELP=0 or HARNESS_DEFINE_CHECK_FAST=0.

HARNESS_LINT      ?= @echo "lint: not configured" && false
HARNESS_TYPECHECK ?= @true
HARNESS_TEST_ALL  ?= @echo "test: not configured" && false
HARNESS_TEST_ONE  ?= @echo "test T=: not configured" && false
HARNESS_SMOKE     ?= @echo "smoke: no runnable surface"
HARNESS_SETUP     ?= bash scripts/harness/setup.sh
HARNESS_SEED      ?= @echo "seed: not configured" && false
HARNESS_RESET     ?= @echo "reset: not configured" && false
HARNESS_DEV       ?= @echo "dev: not configured" && false
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

ifneq ($(HARNESS_DEFINE_HELP),0)
ifeq ($(.DEFAULT_GOAL),)
.DEFAULT_GOAL := help
endif
.PHONY: help
help: ## List targets (delete this one if your Makefile already defines help)
	@echo "Agents: run only these make targets."
	@grep -hE '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS=":.*## "} {printf "  %-14s %s\n", $$1, $$2}'
endif

ifneq ($(HARNESS_DEFINE_CHECK),0)
.PHONY: check
check: lint typecheck test harness-lint ## Completion gate: lint + typecheck + all tests + harness lint
	@echo "check: OK"
endif

ifneq ($(HARNESS_DEFINE_CHECK_FAST),0)
.PHONY: check-fast
check-fast: lint typecheck ## Quick gate (< 60 s): lint + typecheck + tests for changed files if configured
ifneq ($(strip $(HARNESS_TEST_CHANGED)),)
	$(HARNESS_TEST_CHANGED) $(CHANGED)
endif
	@echo "check-fast: OK"
endif

ifneq ($(HARNESS_DEFINE_LINT),0)
.PHONY: lint
lint: ## Lint
	$(HARNESS_LINT)
endif

ifneq ($(HARNESS_DEFINE_TYPECHECK),0)
.PHONY: typecheck
typecheck: ## Type check
	$(HARNESS_TYPECHECK)
endif

ifneq ($(HARNESS_DEFINE_TEST),0)
.PHONY: test
test: ## All tests, or one file/test with T=<path>
ifeq ($(strip $(T)),)
	$(HARNESS_TEST_ALL)
else
	$(HARNESS_TEST_ONE) $(T)
endif
endif

ifneq ($(HARNESS_DEFINE_SMOKE),0)
.PHONY: smoke
smoke: ## Start the app and hit one real path
	$(HARNESS_SMOKE)
endif

ifneq ($(HARNESS_DEFINE_HARNESS_LINT),0)
.PHONY: harness-lint
harness-lint: ## Structural checks on the harness files themselves
	@bash scripts/harness/lint.sh
endif

ifneq ($(HARNESS_DEFINE_SETUP),0)
.PHONY: setup
setup: ## One-time local setup
	$(HARNESS_SETUP)
endif

ifneq ($(HARNESS_DEFINE_SEED),0)
.PHONY: seed
seed: ## Load local sample data (local targets only)
	$(HARNESS_SEED)
endif

ifneq ($(HARNESS_DEFINE_RESET),0)
.PHONY: reset
reset: ## Reset local state (local targets only)
	$(HARNESS_RESET)
endif

ifneq ($(HARNESS_DEFINE_DEV),0)
.PHONY: dev
dev: ## Start the dev server
	$(HARNESS_DEV)
endif

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
