#!/usr/bin/env bats

load test_helper

# help and version

@test "help and no arguments print usage" {
	run shtl help
	[ "$status" -eq 0 ]
	[[ $output == *"Usage: shtl ROUTE_NAME"* ]] || false

	run shtl
	[ "$status" -eq 0 ]
	[[ $output == *"Usage: shtl ROUTE_NAME"* ]] || false
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
	[[ $output == *"No routes to clean"* ]] || false
}

@test "clean has nothing to do when every directory exists" {
	shtl add a "$DIR_A"
	run shtl clean
	[ "$status" -eq 0 ]
	[[ $output == *"All routes point to existing directories"* ]] || false
}

@test "clean skips persistent routes with missing directories" {
	shtl add old "$MISSING_DIR" --persist
	run shtl clean
	[ "$status" -eq 0 ]
	[[ $output == *"All routes point to existing directories"* ]] || false
}

@test "clean refuses to run without a terminal" {
	mkdir "$MISSING_DIR"
	shtl add old "$MISSING_DIR"
	rmdir "$MISSING_DIR"
	run shtl clean < /dev/null
	[ "$status" -eq 1 ]
	[[ $output == *"needs an interactive terminal"* ]] || false
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
	[[ $output == *"status=1"* ]] || false
	[[ $output == *"$DIR_B" ]] || false
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
	[[ $output == *"$DIR_B" ]] || false
}

@test "tab completion offers routes and directories for update in bash" {
	shtl add work "$DIR_A"
	run bash -c 'eval "$(shtl init)"
		COMP_WORDS=(shtl update ""); COMP_CWORD=2; _shtl; echo "${COMPREPLY[*]}"
		cd "$1"; COMP_WORDS=(shtl update work ""); COMP_CWORD=3; _shtl; echo "${COMPREPLY[*]}"' _ "$BATS_TEST_TMPDIR"
	[ "${lines[0]}" = "work" ]
	[[ ${lines[1]} == *a* && ${lines[1]} == *b* ]] || false
}

# A folder under a route (#5)

@test "path takes a folder under the route" {
	mkdir -p "$DIR_A/code/tocsin"
	shtl add work "$DIR_A"
	run shtl path work code/tocsin
	[ "$status" -eq 0 ]
	[ "$output" = "$DIR_A/code/tocsin" ]
	run shtl path work code/
	[ "$output" = "$DIR_A/code" ]
}

@test "path fails for a folder under the route that doesn't exist" {
	shtl add work "$DIR_A"
	run shtl path work nope
	[ "$status" -eq 1 ]
	[[ $output == *"$DIR_A/nope"*"does not exist"* ]] || false
}

@test "path rejects an absolute folder under the route" {
	shtl add work "$DIR_A"
	run shtl path work /tmp
	[ "$status" -eq 1 ]
	[[ $output == *"relative to the route"* ]] || false
}

@test "a folder under a ~/ route" {
	use_test_home
	mkdir -p "$HOME/work/code"
	shtl add work "$HOME/work"
	run shtl path work code
	[ "$output" = "$HOME/work/code" ]
}

@test "shtl ROUTE SUBDIR without the shell function prints the path" {
	mkdir -p "$DIR_A/code"
	shtl add work "$DIR_A"
	run --separate-stderr shtl work code
	[ "$output" = "$DIR_A/code" ]
}

@test "the shell function goes to a folder under a route in bash" {
	mkdir -p "$DIR_A/code/tocsin"
	shtl add work "$DIR_A"
	run bash -c 'eval "$(shtl init)" && shtl work code/tocsin && pwd'
	[ "$status" -eq 0 ]
	[ "$output" = "$DIR_A/code/tocsin" ]
}

@test "the shell function goes to a folder under a route in zsh" {
	command -v zsh > /dev/null || skip "zsh not installed"
	mkdir -p "$DIR_A/code/tocsin"
	shtl add work "$DIR_A"
	run zsh -c 'eval "$(shtl init)" && shtl work code/tocsin && pwd'
	[ "$status" -eq 0 ]
	[ "$output" = "$DIR_A/code/tocsin" ]
}

@test "the shell function stays put for a missing folder under a route" {
	shtl add work "$DIR_A"
	run bash -c 'cd "$1" && eval "$(shtl init)"; shtl work nope; echo "status=$?"; pwd' _ "$DIR_B"
	[[ $output == *"status=1"* ]] || false
	[[ $output == *"$DIR_B" ]] || false
}

@test "tab completion offers folders under a route in bash" {
	mkdir -p "$DIR_A/code/tocsin" "$DIR_A/code/other" "$DIR_A/docs"
	touch "$DIR_A/file"
	shtl add work "$DIR_A"
	run bash -c 'eval "$(shtl init)"
		COMP_WORDS=(shtl work ""); COMP_CWORD=2; _shtl; printf "%s " "${COMPREPLY[@]}"; echo
		COMP_WORDS=(shtl work code/); COMP_CWORD=2; _shtl; printf "%s " "${COMPREPLY[@]}"; echo
		COMP_WORDS=(shtl path work d); COMP_CWORD=3; _shtl; printf "%s " "${COMPREPLY[@]}"; echo'
	[[ ${lines[0]} == *"code/"* && ${lines[0]} == *"docs/"* && ${lines[0]} != *file* ]] || false
	[[ ${lines[1]} == *"code/tocsin/"* && ${lines[1]} == *"code/other/"* ]] || false
	[ "${lines[2]}" = "docs/ " ]
}

@test "tab completion offers nothing under an unknown route in bash" {
	run bash -c 'eval "$(shtl init)"
		COMP_WORDS=(shtl nope ""); COMP_CWORD=2; _shtl; echo "n=${#COMPREPLY[@]}"'
	[ "$output" = "n=0" ]
}

@test "tab completion goes into folders under a route in zsh" {
	command -v zsh > /dev/null || skip "zsh not installed"
	command -v expect > /dev/null || skip "expect not installed"
	mkdir -p "$DIR_A/codebases/project-tocsin" "$DIR_A/docs"
	shtl add work "$DIR_A"
	# Types "shtl work cod<Tab>p<Tab><Enter>" in an interactive zsh, then
	# prints the directory it ended up in. The $ expressions are for zsh and
	# expect, not bash.
	# shellcheck disable=SC2016
	run expect -c '
		set timeout 5
		log_user 0
		spawn env TERM=dumb zsh -f -i
		send "autoload -Uz compinit; compinit -u; eval \"\$(shtl init)\"; PS1=\"> \"; unsetopt beep\r"
		expect "> "
		send "shtl work cod\t"
		sleep 0.5
		send "p\t"
		sleep 0.5
		send "\r"
		expect "> "
		send "print -r -- @@\$PWD@@\r"
		expect -re {@@(/[^@]*)@@}
		puts $expect_out(1,string)
		send "exit\r"'
	[ "$status" -eq 0 ]
	[ "$output" = "$DIR_A/codebases/project-tocsin" ]
}
