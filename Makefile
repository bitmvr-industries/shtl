# Note: Makefile(s) require specific indentiation
# Execute the following in VIM to meet the specification
## set tabstop=4 
## set noexpandtab

NAME=shtl
VERSION=`cat VERSION`

LIB_FILES=`find "./lib" -type f -name "*.sh"`
SRC_FILES=`find "./src" -type f -name "*.sh"`
SCRIPT_FILES=`find "./scripts" -type f -name "*.sh"`
TEST_FILES=`find "./test" -type f -name "*.bash" -o -type f -name "*.bats"`
HOOK_FILES=`find "./.githooks" -type f`
TIMESTAMP=`date -u +"%Y-%m-%dT%H:%M:%SZ"`
EXECUTABLE="shtl"
BUILD_DIR="build"
# Per-user install, no sudo. Override for a system-wide install:
# sudo make install PREFIX=/usr/local
PREFIX ?= $(HOME)/.local
BIN_DIR=$(PREFIX)/bin

build:
	@echo "$(TIMESTAMP) - Build: Starting"
	@mkdir -p $(BUILD_DIR)
	@echo "#!/usr/bin/env bash" > $(BUILD_DIR)/shebang
	@cat $(LIB_FILES) $(SRC_FILES) | awk '!/^source/' | awk '!/#!/' | sed "s/__SHTL_VERSION__/$(VERSION)/" > $(BUILD_DIR)/$(EXECUTABLE)
	@cat $(BUILD_DIR)/shebang $(BUILD_DIR)/$(EXECUTABLE) > $(EXECUTABLE)
	@rm -rf $(BUILD_DIR)
	@chmod +x $(EXECUTABLE)
	@echo "$(TIMESTAMP) - Build: Finished"

clean:
	@echo "$(TIMESTAMP) - Clean: Starting"
	@rm -f $(EXECUTABLE)
	@rm -rf $(BUILD_DIR)
	@echo "$(TIMESTAMP) - Clean: Finished"

install: build
	@echo "$(TIMESTAMP) - Install: Starting"
	@mkdir -p "$(BIN_DIR)"
	@cp $(EXECUTABLE) "$(BIN_DIR)/$(EXECUTABLE)"
	@echo "$(TIMESTAMP) - Install: Installed to $(BIN_DIR)/shtl"
	@case ":$$PATH:" in *":$(BIN_DIR):"*) ;; *) echo "$(TIMESTAMP) - Install: Warning: $(BIN_DIR) is not on your PATH" ;; esac
	@echo "$(TIMESTAMP) - Install: Complete"
	@bash scripts/shell_setup.sh install

uninstall:
	@echo "$(TIMESTAMP) - Uninstall: Starting"
	@rm -f "$(BIN_DIR)/$(EXECUTABLE)"
	@echo "$(TIMESTAMP) - Uninstall: Complete"
	@bash scripts/shell_setup.sh uninstall

lint:
	@echo "$(TIMESTAMP) - Lint: Starting"
	@shellcheck -x $(LIB_FILES) $(SRC_FILES) $(SCRIPT_FILES) $(TEST_FILES) $(HOOK_FILES)
	@echo "$(TIMESTAMP) - Lint: Finished"

test: build
	@command -v bats > /dev/null || { echo "$(TIMESTAMP) - Test: bats not found. Install it with: brew install bats-core"; exit 1; }
	@bats test

# Runs lint and the tests before every push (see .githooks/pre-push)
hooks:
	@git config core.hooksPath .githooks
	@echo "$(TIMESTAMP) - Hooks: Enabled. Lint and tests now run before each push"

.PHONY: build clean install uninstall lint test hooks

