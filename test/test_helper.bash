# Shared setup for the bats tests. Tests run the built ./shtl (make test
# builds it first) against a throwaway config dir, never your real routes.

bats_require_minimum_version 1.5.0

# The variables set in setup are used by the .bats files that load this
# shellcheck disable=SC2034

setup() {
	REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
	PATH="$REPO_DIR:$PATH"

	export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
	ROUTES_FILE="$XDG_CONFIG_HOME/shtl/routes"

	# Real directories for routes to point at
	DIR_A="$BATS_TEST_TMPDIR/a"
	DIR_B="$BATS_TEST_TMPDIR/b"
	mkdir -p "$DIR_A" "$DIR_B"
	MISSING_DIR="$BATS_TEST_TMPDIR/missing"
}

# Prints the route entries, without the header line
routes() {
	grep -v '^#' "$ROUTES_FILE"
}

# Points HOME at a throwaway directory for the rest of the test
use_test_home() {
	export HOME="$BATS_TEST_TMPDIR/home"
	mkdir -p "$HOME"
}
