.PHONY: diagram help lint-md lint format-md format bootstrap-dry-run preflight

help:
	@echo "Available targets:"
	@echo "  make diagram            Generate homelab architecture diagram (PNG)"
	@echo "  make preflight          Audit VM network, resources, kernel, and ports"
	@echo "  make lint-md            Lint markdown files using markdownlint-cli"
	@echo "  make format-md          Format/fix markdown files using markdownlint-cli"
	@echo "  make bootstrap-dry-run  Test bootstrap automation scripts in dry-run mode"

diagram:
	uv run scripts/generate_diagram.py

lint: lint-md

lint-md:
	npx markdownlint-cli "**/*.md"

format: format-md

format-md:
	npx markdownlint-cli --fix "**/*.md"

preflight:
	./bootstrap/00-preflight.sh

bootstrap-dry-run:
	@echo "Testing bootstrap suite in dry-run mode..."
	./bootstrap/00-preflight.sh --dry-run
	./bootstrap/01-prerequisites.sh --dry-run
	./bootstrap/02-k3s-server.sh --dry-run
	./bootstrap/03-cni-cilium.sh --dry-run
	./bootstrap/04-k3s-agent.sh --dry-run
