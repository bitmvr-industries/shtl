# Note: Makefile(s) require specific indentiation
# Execute the following in VIM to meet the specification
## set tabstop=4 
## set noexpandtab

NAME=shtl
VERSION=1.0.0

LIB_FILES=`find "./lib" -type f -name "*.sh"`
SRC_FILES=`find "./src" -type f -name "*.sh"`
TIMESTAMP=`date -u +"%Y-%m-%dT%H:%M:%SZ"`
EXECUTABLE="shtl"
BUILD_DIR="build"
INSTALL_DIR="/usr/local/shtl"
SYMLINK_DIR="/usr/local/bin"

build:
	@echo "$(TIMESTAMP) - Build: Starting"
	@mkdir -p $(BUILD_DIR)
	@echo "#!/usr/bin/env bash" > $(BUILD_DIR)/shebang
	@cat $(LIB_FILES) $(SRC_FILES) | awk '!/^source/' | awk '!/#!/' > $(BUILD_DIR)/$(EXECUTABLE)
	@cat $(BUILD_DIR)/shebang $(BUILD_DIR)/$(EXECUTABLE) > $(EXECUTABLE)
	@rm -rf $(BUILD_DIR)
	@chmod +x $(EXECUTABLE)
	@echo "$(TIMESTAMP) - Build: Finished"

clean:
	@echo "$(TIMESTAMP) - Clean: Starting"
	@rm -f $(EXECUTABLE)
	@rm -rf $(BUILD_DIR)
	@echo "$(TIMESTAMP) - Clean: Finished"

install:
	@echo "$(TIMESTAMP) - Install: Starting"
	@sudo mkdir -p $(INSTALL_DIR)
	@sudo chown $(USER):admin $(INSTALL_DIR)
	@cp $(EXECUTABLE) $(INSTALL_DIR)
	@sudo chown $(USER):admin $(INSTALL_DIR)/$(EXECUTABLE)
	@ln -sf "$(INSTALL_DIR)/$(EXECUTABLE)" "$(SYMLINK_DIR)/$(EXECUTABLE)"
	@echo "$(TIMESTAMP) - Install: Complete"

lint:
	@echo "$(TIMESTAMP) - Lint: Starting"
	@shellcheck -x $(CONF_FILES) $(LIB_FILES) $(SRC_FILES)
	@echo "$(TIMESTAMP) - Lint: Finished"

.PHONY: build clean install lint

