# ------------------------------------------------------------------------------
# Help
# ------------------------------------------------------------------------------

##@ General

.PHONY: help
help: ## Display this help message
	@awk 'BEGIN {FS = ":.*##"; printf "\n\033[1mKubernetes Homelab Management\033[0m\n\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1;34m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)

# ------------------------------------------------------------------------------
# Documentation
# ------------------------------------------------------------------------------

##@ Documentation

.PHONY: docs-serve docs-build

docs-serve: ## Launch live Zensical preview using Podman (http://localhost:8000)
	podman run --rm -it -p 8000:8000 -v .:/docs:Z zensical/zensical

docs-build: ## Build static Zensical documentation site using Podman
	podman run --rm -v .:/docs:Z zensical/zensical build

# ------------------------------------------------------------------------------
# Markdown Tooling
# ------------------------------------------------------------------------------

##@ Markdown Tooling

SUPPORTED_GOALS := lint-md lint format-md format
ifeq ($(filter $(firstword $(MAKECMDGOALS)),$(SUPPORTED_GOALS)),$(firstword $(MAKECMDGOALS)))
  TARGET_ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
  $(eval .PHONY: $(TARGET_ARGS))
  $(eval $(TARGET_ARGS):;@:)
endif

TARGET_PATHS ?= $(if $(TARGET_ARGS),$(TARGET_ARGS),"**/*.md")

.PHONY: format-md lint-md

format-md: ## Format/fix markdown files using markdownlint-cli
	npx markdownlint-cli --fix $(TARGET_PATHS)

lint-md: ## Lint markdown files using markdownlint-cli
	npx markdownlint-cli $(TARGET_PATHS)

# ------------------------------------------------------------------------------
# Architecture Diagrams
# ------------------------------------------------------------------------------

##@ Architecture Diagrams

.PHONY: diagram

diagram: ## Generate homelab architecture diagram (PNG)
	uv run scripts/generate_diagram.py

# ------------------------------------------------------------------------------
# Cluster Bootstrap & Validation
# ------------------------------------------------------------------------------

##@ Cluster Bootstrap & Validation

.PHONY: preflight bootstrap-dry-run

preflight: ## Audit VM network, resources, kernel, and ports
	./bootstrap/00-preflight.sh

bootstrap-dry-run: ## Test bootstrap automation scripts in dry-run mode
	@echo "Testing bootstrap suite in dry-run mode..."
	./bootstrap/00-preflight.sh --dry-run
	./bootstrap/01-k3s-server.sh --dry-run
	./bootstrap/02-k3s-agent.sh --dry-run --server-url "https://127.0.0.1:6443" --token "dummy-token" --node-role "app"
	./bootstrap/03-cni-cilium.sh --dry-run

# ------------------------------------------------------------------------------
# General Formatting & Linting
# ------------------------------------------------------------------------------

##@ General Formatting & Linting

.PHONY: format lint

format: format-md ## Run all formatters
lint: lint-md ## Run all linters
