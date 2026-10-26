# Agents: run only make targets listed here. No direct shell commands.
# harness.mk — verification targets agents rely on. Include from the root Makefile:   include harness.mk
# Point the HARNESS_* variables at this repo's real commands (keep them quiet on success).
# To keep a target your Makefile already defines, set HARNESS_DEFINE_<NAME>=0 before the include
# (NAME upper-case, - becomes _), e.g. HARNESS_DEFINE_HELP=0 or HARNESS_DEFINE_CHECK_FAST=0.
# Include harness.mk after your own default target (an early include makes its first target the default goal).

HARNESS_MK := $(lastword $(MAKEFILE_LIST))
_HARNESS_TARGETS :=

HARNESS_LINT      ?= @echo "lint: not configured" && false
HARNESS_TYPECHECK ?= @true
HARNESS_TEST_ALL  ?= @echo "test: not configured" && false
HARNESS_TEST_ONE  ?= @echo "test T=: not configured" && false
HARNESS_SMOKE     ?= @echo "smoke: no runnable surface"
HARNESS_SETUP     ?= bash scripts/harness/setup.sh
# seed, reset and dev exist only when set ABOVE the include: unconfigured, `make seed` says "No rule"
# and `make setup` skips the step (a defined-but-failing default would break setup).
HARNESS_SEED      ?=
HARNESS_RESET     ?=
HARNESS_DEV       ?=
# Tests for changed files only (receives the file list). Leave empty to skip tests in check-fast.
HARNESS_TEST_CHANGED ?=
# Files changed vs the base branch (used by check-fast): origin/HEAD, else origin/main, else origin/master
HARNESS_BASE      ?= $(or $(shell git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null),$(if $(shell git rev-parse -q --verify origin/main 2>/dev/null),origin/main,origin/master))
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
_HARNESS_TARGETS += help
_HELP_help := List targets (delete this one if your Makefile already defines help)
help: ## List targets (delete this one if your Makefile already defines help)
	@echo "Agents: run only these make targets."
	@$(foreach t,$(_HARNESS_TARGETS),printf '  %-14s %s\n' '$(t)' '$(_HELP_$(t))';)
	@grep -hE '^[a-zA-Z0-9_-]+:.*## ' $(filter-out $(HARNESS_MK),$(MAKEFILE_LIST)) | awk 'BEGIN {FS=":.*## "} {printf "  %-14s %s\n", $$1, $$2}' || true
endif

ifneq ($(HARNESS_DEFINE_CHECK),0)
.PHONY: check
_HARNESS_TARGETS += check
_HELP_check := Completion gate: lint + typecheck + all tests + harness lint
check: lint typecheck test harness-lint ## Completion gate: lint + typecheck + all tests + harness lint
	@echo "check: OK"
endif

ifneq ($(HARNESS_DEFINE_CHECK_FAST),0)
.PHONY: check-fast
_HARNESS_TARGETS += check-fast
_HELP_check-fast := Quick gate (< 60 s): lint + typecheck + tests for changed files if configured
check-fast: lint typecheck ## Quick gate (< 60 s): lint + typecheck + tests for changed files if configured
ifneq ($(strip $(HARNESS_TEST_CHANGED)),)
	$(HARNESS_TEST_CHANGED) $(CHANGED)
endif
	@echo "check-fast: OK"
endif

ifneq ($(HARNESS_DEFINE_LINT),0)
.PHONY: lint
_HARNESS_TARGETS += lint
_HELP_lint := Lint
lint: ## Lint
	$(HARNESS_LINT)
endif

ifneq ($(HARNESS_DEFINE_TYPECHECK),0)
.PHONY: typecheck
_HARNESS_TARGETS += typecheck
_HELP_typecheck := Type check
typecheck: ## Type check
	$(HARNESS_TYPECHECK)
endif

ifneq ($(HARNESS_DEFINE_TEST),0)
.PHONY: test
_HARNESS_TARGETS += test
_HELP_test := All tests, or one file/test with T=<path>
test: ## All tests, or one file/test with T=<path>
ifeq ($(strip $(T)),)
	$(HARNESS_TEST_ALL)
else
	$(HARNESS_TEST_ONE) $(T)
endif
endif

ifneq ($(HARNESS_DEFINE_SMOKE),0)
.PHONY: smoke
_HARNESS_TARGETS += smoke
_HELP_smoke := Start the app and hit one real path
smoke: ## Start the app and hit one real path
	$(HARNESS_SMOKE)
endif

ifneq ($(HARNESS_DEFINE_HARNESS_LINT),0)
.PHONY: harness-lint
_HARNESS_TARGETS += harness-lint
_HELP_harness-lint := Structural checks on the harness files themselves
harness-lint: ## Structural checks on the harness files themselves
	@bash scripts/harness/lint.sh
endif

ifneq ($(HARNESS_DEFINE_SETUP),0)
.PHONY: setup
_HARNESS_TARGETS += setup
_HELP_setup := One-time local setup
setup: ## One-time local setup
	$(HARNESS_SETUP)
endif

ifneq ($(HARNESS_DEFINE_SEED),0)
ifneq ($(strip $(HARNESS_SEED)),)
.PHONY: seed
_HARNESS_TARGETS += seed
_HELP_seed := Load local sample data (local targets only)
seed: ## Load local sample data (local targets only)
	@if [ -f scripts/harness/local-guard.sh ]; then bash scripts/harness/local-guard.sh || exit 1; elif [ "$$HARNESS_ALLOW_SEED" = 1 ]; then echo "seed: local-guard.sh missing, proceeding (HARNESS_ALLOW_SEED=1)" >&2; else echo "seed: scripts/harness/local-guard.sh missing — refusing (install it, or HARNESS_ALLOW_SEED=1)" >&2; exit 1; fi
	$(HARNESS_SEED)
endif
endif

ifneq ($(HARNESS_DEFINE_RESET),0)
ifneq ($(strip $(HARNESS_RESET)),)
.PHONY: reset
_HARNESS_TARGETS += reset
_HELP_reset := Reset local state (local targets only)
reset: ## Reset local state (local targets only)
	@if [ -f scripts/harness/local-guard.sh ]; then bash scripts/harness/local-guard.sh || exit 1; elif [ "$$HARNESS_ALLOW_SEED" = 1 ]; then echo "reset: local-guard.sh missing, proceeding (HARNESS_ALLOW_SEED=1)" >&2; else echo "reset: scripts/harness/local-guard.sh missing — refusing (install it, or HARNESS_ALLOW_SEED=1)" >&2; exit 1; fi
	$(HARNESS_RESET)
endif
endif

ifneq ($(HARNESS_DEFINE_DEV),0)
ifneq ($(strip $(HARNESS_DEV)),)
.PHONY: dev
_HARNESS_TARGETS += dev
_HELP_dev := Start the dev server
dev: ## Start the dev server
	$(HARNESS_DEV)
endif
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
