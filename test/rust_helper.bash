# Shared setup for the bats tests of the Rust shtl (2.0): the shell function
# and completion. Tests run the debug build (make test builds it first)
# against a throwaway config dir, never your real routes.

bats_require_minimum_version 1.5.0

# The variables set in setup are used by the .bats files that load this
# shellcheck disable=SC2034

setup() {
	REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
	PATH="${CARGO_TARGET_DIR:-$REPO_DIR/target}/debug:$PATH"

	export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
	ROUTES_FILE="$XDG_CONFIG_HOME/shtl/routes.toml"

	# Real directories for routes to point at
	DIR_A="$BATS_TEST_TMPDIR/a"
	DIR_B="$BATS_TEST_TMPDIR/b"
	mkdir -p "$DIR_A" "$DIR_B"
}

# This machine's host name, the way shtl reads it
this_host() {
	if [[ $(uname) == Darwin ]]; then
		scutil --get LocalHostName
	else
		hostname | cut -d. -f1
	fi
}

# Adds a route to the routes file: add_route NAME PATH [HOST]
add_route() {
	mkdir -p "$(dirname "$ROUTES_FILE")"
	[[ -f $ROUTES_FILE ]] || echo 'version = 2' > "$ROUTES_FILE"
	printf '\n[[route]]\nname = "%s"\npath = "%s"\n' "$1" "$2" >> "$ROUTES_FILE"
	if [[ -n ${3:-} ]]; then
		printf 'hosts = ["%s"]\n' "$3" >> "$ROUTES_FILE"
	fi
}
