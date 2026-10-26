# Workspace Makefile — agents run these from the workspace root. Each target delegates to the member repos' own harness.
.DEFAULT_GOAL := help
.PHONY: help status changed check check-fast setup claude-md test branch bootstrap harness-lint

help: ## List targets
	@echo "Workspace: run these from here, or 'make -C <repo> <target>' inside one repo."
	@grep -hE '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS=":.*## "} {printf "  %-12s %s\n", $$1, $$2}'
status: ## Branch, uncommitted files, commits ahead, harness present — per repo
	@bash ws.sh status
changed: ## Repos with changes (uncommitted or ahead of base)
	@bash ws.sh changed
check: ## Run 'make check' in every changed repo (the done gate)
	@bash ws.sh check
check-fast: ## Run 'make check-fast' in every changed repo
	@bash ws.sh check-fast
test: ## One repo's tests: make test R=<repo> [T=<path>]
	@bash ws.sh test $(R) $(T)
branch: ## Same branch in the repos a feature touches: make branch B=<name> R="<repo> <repo>"
	@bash ws.sh branch $(B) $(R)
bootstrap: ## Clone any manifest repo that is missing
	@bash ws.sh bootstrap
harness-lint: ## Check the workspace map and that every repo has a harness
	@bash ws.sh lint
setup: ## Run each present repo's setup, in merge order
	@bash ws.sh setup
claude-md: ## Rewrite CLAUDE.md to import AGENTS.md, INVARIANTS.md and each present repo's INVARIANTS.md
	@bash ws.sh claude-md
