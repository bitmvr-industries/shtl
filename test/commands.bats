#!/usr/bin/env bats

load test_helper

# help and version

@test "help and no arguments print usage" {
	run shtl help
	[ "$status" -eq 0 ]
	[[ $output == *"Usage: shtl ROUTE_NAME"* ]]

	run shtl
	[ "$status" -eq 0 ]
	[[ $output == *"Usage: shtl ROUTE_NAME"* ]]
}

@test "version prints the contents of VERSION" {
	run shtl version
	[ "$status" -eq 0 ]
	[ "$output" = "$(cat "$REPO_DIR/VERSION")" ]
}

# clean (the interactive checklist needs a TTY, so only its other paths are tested)

@test "clean explains when there are no routes" {
	run shtl clean
	[ "$status" -eq 0 ]
	[[ $output == *"No routes to clean"* ]]
}

@test "clean has nothing to do when every directory exists" {
	shtl add a "$DIR_A"
	run shtl clean
	[ "$status" -eq 0 ]
	[[ $output == *"All routes point to existing directories"* ]]
}

@test "clean skips persistent routes with missing directories" {
	shtl add old "$MISSING_DIR" --persist
	run shtl clean
	[ "$status" -eq 0 ]
	[[ $output == *"All routes point to existing directories"* ]]
}

@test "clean refuses to run without a terminal" {
	shtl add old "$MISSING_DIR"
	run shtl clean < /dev/null
	[ "$status" -eq 1 ]
	[[ $output == *"needs an interactive terminal"* ]]
	[ "$(routes)" = "old[]:$MISSING_DIR" ]
}

# init: the shell function

# Each shell parses the whole init output, including the other shell's branch
@test "the init output is valid bash and zsh" {
	shtl init | bash -n
	command -v zsh > /dev/null || skip "zsh not installed"
	shtl init | zsh -n
}

@test "the shell function changes directory to a route in bash" {
	shtl add work "$DIR_A"
	run bash -c 'eval "$(shtl init)" && shtl work && pwd'
	[ "$status" -eq 0 ]
	[ "$output" = "$DIR_A" ]
}

@test "the shell function changes directory to a route in zsh" {
	command -v zsh > /dev/null || skip "zsh not installed"
	shtl add work "$DIR_A"
	run zsh -c 'eval "$(shtl init)" && shtl work && pwd'
	[ "$status" -eq 0 ]
	[ "$output" = "$DIR_A" ]
}

@test "the shell function passes subcommands through" {
	shtl add work "$DIR_A"
	run bash -c 'eval "$(shtl init)" && shtl path work'
	[ "$output" = "$DIR_A" ]
}

@test "the shell function stays put for an unknown route" {
	run bash -c 'cd "$1" && eval "$(shtl init)"; shtl nope; echo "status=$?"; pwd' _ "$DIR_B"
	[[ $output == *"status=1"* ]]
	[[ $output == *"$DIR_B" ]]
}

# Log messages

@test "log messages are one plain line on stderr" {
	run --separate-stderr shtl path nope
	[ "$status" -eq 1 ]
	[ -z "$output" ]
	[ "$stderr" = 'shtl [ERROR] Route "nope" does not exist' ]
}

@test "log messages print backslashes literally" {
	run --separate-stderr shtl path 'x\new'
	[ "$stderr" = 'shtl [ERROR] Route "x\new" does not exist' ]
}

@test "the shell function passes update through" {
	shtl add work "$DIR_A"
	run bash -c 'cd "$1" && eval "$(shtl init)" && shtl update work && shtl path work' _ "$DIR_B"
	[ "$status" -eq 0 ]
	[[ $output == *"$DIR_B" ]]
}

@test "tab completion offers routes and directories for update in bash" {
	shtl add work "$DIR_A"
	run bash -c 'eval "$(shtl init)"
		COMP_WORDS=(shtl update ""); COMP_CWORD=2; _shtl; echo "${COMPREPLY[*]}"
		cd "$1"; COMP_WORDS=(shtl update work ""); COMP_CWORD=3; _shtl; echo "${COMPREPLY[*]}"' _ "$BATS_TEST_TMPDIR"
	[ "${lines[0]}" = "work" ]
	[[ ${lines[1]} == *a* && ${lines[1]} == *b* ]]
}
