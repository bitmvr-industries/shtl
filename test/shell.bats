#!/usr/bin/env bats

# The Rust shtl's shell function and tab completion, from shtl init

load rust_helper

# Each shell parses the whole init output, including the other shell's branch
@test "the init output is valid bash and zsh" {
	shtl init | bash -n
	command -v zsh > /dev/null || skip "zsh not installed"
	shtl init | zsh -n
}

@test "the shell function changes directory to a route in bash" {
	add_route work "$DIR_A"
	run bash -c 'eval "$(shtl init)" && shtl work && pwd'
	[ "$status" -eq 0 ]
	[ "$output" = "$DIR_A" ]
}

@test "the shell function changes directory to a route in zsh" {
	command -v zsh > /dev/null || skip "zsh not installed"
	add_route work "$DIR_A"
	run zsh -c 'eval "$(shtl init)" && shtl work && pwd'
	[ "$status" -eq 0 ]
	[ "$output" = "$DIR_A" ]
}

@test "the shell function passes commands through" {
	add_route work "$DIR_A"
	run bash -c 'eval "$(shtl init)" && shtl path work && shtl version'
	[ "${lines[0]}" = "$DIR_A" ]
	[ "${lines[1]}" = "$(shtl version)" ]
}

@test "the shell function stays put for an unknown route" {
	run bash -c 'cd "$1" && eval "$(shtl init)"; shtl nope; echo "status=$?"; pwd' _ "$DIR_B"
	[[ $output == *"status=1"* ]] || false
	[[ $output == *"$DIR_B" ]] || false
}

@test "the shell function goes to a folder under a route in bash" {
	mkdir -p "$DIR_A/code/tocsin"
	add_route work "$DIR_A"
	run bash -c 'eval "$(shtl init)" && shtl work code/tocsin && pwd'
	[ "$status" -eq 0 ]
	[ "$output" = "$DIR_A/code/tocsin" ]
}

@test "the shell function goes to a folder under a route in zsh" {
	command -v zsh > /dev/null || skip "zsh not installed"
	mkdir -p "$DIR_A/code/tocsin"
	add_route work "$DIR_A"
	run zsh -c 'eval "$(shtl init)" && shtl work code/tocsin && pwd'
	[ "$status" -eq 0 ]
	[ "$output" = "$DIR_A/code/tocsin" ]
}

@test "the shell function stays put for a missing folder under a route" {
	add_route work "$DIR_A"
	run bash -c 'cd "$1" && eval "$(shtl init)"; shtl work nope; echo "status=$?"; pwd' _ "$DIR_B"
	[[ $output == *"status=1"* ]] || false
	[[ $output == *"$DIR_B" ]] || false
}

@test "tab completion offers commands and this host's routes in bash" {
	add_route work "$DIR_A"
	add_route away "$DIR_B" not-this-host
	run bash -c 'eval "$(shtl init)"
		COMP_WORDS=(shtl ""); COMP_CWORD=1; _shtl; echo " ${COMPREPLY[*]} "'
	[[ $output == *" work "* && $output == *" doctor "* && $output == *" ls "* ]] || false
	[[ $output != *away* ]] || false
}

@test "tab completion offers routes for commands that take a route in bash" {
	add_route work "$DIR_A"
	run bash -c 'eval "$(shtl init)"
		for c in remove rm update persist path; do
			COMP_WORDS=(shtl "$c" ""); COMP_CWORD=2; _shtl; echo "${COMPREPLY[*]}"
		done'
	[ "$output" = "$(printf 'work\nwork\nwork\nwork\nwork')" ]
}

@test "tab completion offers directories for the path of add and update in bash" {
	mkdir -p "$DIR_A/one" "$DIR_A/two"
	touch "$DIR_A/file"
	run bash -c 'cd "$1"; eval "$(shtl init)"
		COMP_WORDS=(shtl add x ""); COMP_CWORD=3; _shtl; echo "${COMPREPLY[*]}"
		COMP_WORDS=(shtl update x t); COMP_CWORD=3; _shtl; echo "${COMPREPLY[*]}"' _ "$DIR_A"
	[[ " ${lines[0]} " == *" one "* && " ${lines[0]} " == *" two "* && ${lines[0]} != *file* ]] || false
	[ "${lines[1]}" = "two" ]
}

@test "tab completion offers folders under a route in bash" {
	mkdir -p "$DIR_A/code/tocsin" "$DIR_A/code/other" "$DIR_A/docs"
	touch "$DIR_A/file"
	add_route work "$DIR_A"
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
	add_route work "$DIR_A"
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
