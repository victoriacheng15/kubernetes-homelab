.PHONY: diagram help lint-md lint format-md format

help:
	@echo "Available targets:"
	@echo "  make diagram    Generate homelab architecture diagram (PNG)"
	@echo "  make lint-md    Lint markdown files using markdownlint-cli"
	@echo "  make format-md  Format/fix markdown files using markdownlint-cli"

diagram:
	uv run scripts/generate_diagram.py

lint: lint-md

lint-md:
	npx markdownlint-cli "**/*.md"

format: format-md

format-md:
	npx markdownlint-cli --fix "**/*.md"
