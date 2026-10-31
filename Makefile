# Note: Makefile(s) require specific indentiation
# Execute the following in VIM to meet the specification
## set tabstop=4
## set noexpandtab

NAME=shtl
TEST_FILES=`find "./test" -type f -name "*.bash" -o -type f -name "*.bats"`
HOOK_FILES=`find "./.githooks" -type f`
TIMESTAMP=`date -u +"%Y-%m-%dT%H:%M:%SZ"`
RELEASE_BIN=target/release/$(NAME)
# Per-user install, no sudo. Override for a system-wide install:
# sudo make install PREFIX=/usr/local
PREFIX ?= $(HOME)/.local
BIN_DIR=$(PREFIX)/bin

build:
	@echo "$(TIMESTAMP) - Build: Starting"
	@cargo build --release --quiet
	@echo "$(TIMESTAMP) - Build: Finished: $(RELEASE_BIN)"

clean:
	@echo "$(TIMESTAMP) - Clean: Starting"
	@cargo clean --quiet
	@echo "$(TIMESTAMP) - Clean: Finished"

install: build
	@echo "$(TIMESTAMP) - Install: Starting"
	@mkdir -p "$(BIN_DIR)"
	@cp $(RELEASE_BIN) "$(BIN_DIR)/$(NAME)"
	@echo "$(TIMESTAMP) - Install: Installed to $(BIN_DIR)/$(NAME)"
	@case ":$$PATH:" in *":$(BIN_DIR):"*) ;; *) echo "$(TIMESTAMP) - Install: Warning: $(BIN_DIR) is not on your PATH" ;; esac
	@echo "$(TIMESTAMP) - Install: Complete"
	@echo ""
	@"$(BIN_DIR)/$(NAME)" setup

uninstall: build
	@echo "$(TIMESTAMP) - Uninstall: Starting"
	@$(RELEASE_BIN) unsetup
	@echo ""
	@rm -f "$(BIN_DIR)/$(NAME)"
	@echo "$(TIMESTAMP) - Uninstall: Complete"

lint:
	@echo "$(TIMESTAMP) - Lint: Starting"
	@cargo fmt --check
	@cargo clippy --all-targets --quiet -- -D warnings
	@shellcheck -x install.sh $(TEST_FILES) $(HOOK_FILES)
	@# bash 3.2 (macOS) doesn't fail a test on a false [[ ]] unless it's the last line
	@! grep -nE '^[[:space:]]+\[\[ .* \]\][[:space:]]*$$' $(TEST_FILES) || { echo "$(TIMESTAMP) - Lint: End these test assertions with || false"; exit 1; }
	@echo "$(TIMESTAMP) - Lint: Finished"

# Unit and integration tests, then the bats tests of the shell function,
# clean and setup, which run the debug build
test:
	@command -v bats > /dev/null || { echo "$(TIMESTAMP) - Test: bats not found. Install it with: brew install bats-core"; exit 1; }
	@cargo test --quiet
	@cargo build --quiet
	@bats test

# Runs lint and the tests before every push (see .githooks/pre-push)
hooks:
	@git config core.hooksPath .githooks
	@echo "$(TIMESTAMP) - Hooks: Enabled. Lint and tests now run before each push"

.PHONY: build clean install uninstall lint test hooks
