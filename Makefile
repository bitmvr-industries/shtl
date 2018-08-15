# Note: Makefile(s) require specific indentiation
# Execute the following in VIM to meet the specification
## set tabstop=4 
## set noexpandtab

NAME=shtl
VERSION=1.0.0

CONF_FILES=`find "./config" -type f -name "*.conf"`
LIB_FILES=`find "./lib" -type f -name "*.sh"`
SRC_FILES=`find "./src" -type f -name "*.sh"`
EXECUTABLE="shtl.sh"
BUILD_DIR="build"

build:
	mkdir -p $(BUILD_DIR)
	echo "#!/usr/bin/env bash" > $(BUILD_DIR)/shebang
	cat $(CONF_FILES) $(LIB_FILES) $(SRC_FILES) | awk '!/^source/' | awk '!/#!/' > $(BUILD_DIR)/$(EXECUTABLE)
	cat $(BUILD_DIR)/shebang $(BUILD_DIR)/$(EXECUTABLE) > $(EXECUTABLE)
	rm -rf $(BUILD_DIR)
	chmod +x $(EXECUTABLE)

clean:
	rm -f $(EXECUTABLE)
	rm -rf $(BUILD_DIR)

lint:
	shellcheck -x $(CONF_FILES) $(LIB_FILES) $(SRC_FILES)

.PHONY: build clean lint

