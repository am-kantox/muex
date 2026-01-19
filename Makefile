.PHONY: help build escript archive install-escript install-archive test-install clean

help: ## Show this help message
	@echo "Muex Build Commands"
	@echo "==================="
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

build: ## Build both escript and hex archive
	mix deps.get
	mix compile
	mix escript.build
	mix archive.build
	@echo ""
	@echo "✓ Built successfully:"
	@ls -lh muex muex-*.ez

escript: ## Build escript only
	mix deps.get
	mix compile
	mix escript.build
	@echo "✓ Escript built: muex"

archive: ## Build hex archive only
	mix deps.get
	mix compile
	mix archive.build
	@echo "✓ Archive built: muex-0.2.0.ez"

install-escript: escript ## Build and install escript to /usr/local/bin
	@echo "Installing escript to /usr/local/bin/muex..."
	sudo cp muex /usr/local/bin/muex
	sudo chmod +x /usr/local/bin/muex
	@echo "✓ Installed. Run 'muex --version' to verify."

install-archive: archive ## Build and install hex archive
	@echo "Installing hex archive..."
	mix archive.install muex-0.2.0.ez
	@echo "✓ Installed. Run 'mix muex --version' to verify."

test-install: build ## Test both installation methods
	@echo "Running installation tests..."
	./scripts/test_installations.sh

clean: ## Clean build artifacts
	mix clean
	rm -f muex muex-*.ez
	@echo "✓ Cleaned"

format: ## Format code
	mix format

quality: ## Run quality checks (format, credo, dialyzer)
	mix quality

test: ## Run tests
	mix test

all: clean build test-install ## Clean, build, and test everything
	@echo ""
	@echo "======================================="
	@echo "✓ All build and test steps completed!"
	@echo "======================================="
