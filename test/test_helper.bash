# Shared setup for the bats tests. Tests run the built ./shtl (make test
# builds it first) against a throwaway config dir, never your real routes.

bats_require_minimum_version 1.5.0

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

# Prints the routes file without the trailing blank line shtl keeps
routes() {
	grep -v '^$' "$ROUTES_FILE"
}
