#!/usr/bin/env bats
# Each test sets its own SHELL, and rc file text holds literal $ expressions
# shellcheck disable=SC2030,SC2031,SC2016

load test_helper

# setup and unsetup: they find the rc file for the user's shell and OS. Each
# test uses a throwaway HOME, sets SHELL, and fakes uname to pick the OS.

MARKER="# shtl: https://github.com/bitmvr-industries/shtl"
INIT_LINE='if command -v shtl >/dev/null; then eval "$(shtl init)"; fi'

# Makes uname print $1 (Darwin or Linux) for the rest of the test
fake_os() {
	mkdir -p "$BATS_TEST_TMPDIR/fakebin"
	printf '#!/bin/sh\necho %s\n' "$1" > "$BATS_TEST_TMPDIR/fakebin/uname"
	chmod +x "$BATS_TEST_TMPDIR/fakebin/uname"
	PATH="$BATS_TEST_TMPDIR/fakebin:$PATH"
}

use_bash_on() {
	use_test_home
	fake_os "$1"
	export SHELL=/bin/bash
}

# Runs setup with no terminal: it names the file and edits nothing
setup_target() {
	run shtl setup < /dev/null
	[ "$status" -eq 0 ]
}

# Types $2 at the prompt of `shtl $1` in a terminal
answer() {
	command -v expect > /dev/null || skip "expect not installed"
	run expect -c "
		set timeout 5
		spawn shtl $1
		expect {\[y/N\] }
		send \"$2\r\"
		expect eof"
	[ "$status" -eq 0 ]
}

# Which file

@test "zsh uses ~/.zshrc" {
	use_test_home
	export SHELL=/bin/zsh
	setup_target
	[[ $output == *"lines in ~/.zshrc "* ]] || false
}

@test "zsh uses \$ZDOTDIR/.zshrc when ZDOTDIR is set" {
	use_test_home
	export SHELL=/bin/zsh ZDOTDIR="$HOME/.config/zsh"
	setup_target
	[[ $output == *"lines in ~/.config/zsh/.zshrc "* ]] || false
}

@test "bash on Linux uses ~/.bashrc" {
	use_bash_on Linux
	echo 'export A=1' > "$HOME/.bash_profile"
	setup_target
	[[ $output == *"lines in ~/.bashrc "* ]] || false
}

@test "bash on macOS uses ~/.bash_profile when there is no login file" {
	use_bash_on Darwin
	setup_target
	[[ $output == *"lines in ~/.bash_profile "* ]] || false
}

@test "bash on macOS uses ~/.profile when it is the only login file" {
	use_bash_on Darwin
	echo 'export A=1' > "$HOME/.profile"
	setup_target
	[[ $output == *"lines in ~/.profile "* ]] || false
	[ ! -e "$HOME/.bash_profile" ]
}

@test "bash on macOS uses the login file that bash reads first" {
	use_bash_on Darwin
	echo 'export A=1' > "$HOME/.bash_login"
	echo 'export B=1' > "$HOME/.profile"
	setup_target
	[[ $output == *"lines in ~/.bash_login "* ]] || false
}

@test "bash on macOS uses ~/.bashrc when the login file sources it" {
	use_bash_on Darwin
	local line lines=(
		'source ~/.bashrc'
		'. ~/.bashrc'
		'[ -f ~/.bashrc ] && . ~/.bashrc'
		'[[ -r "$HOME/.bashrc" ]] && source "$HOME/.bashrc"'
		'if [ -f "${HOME}/.bashrc" ]; then . "${HOME}/.bashrc"; fi'
		'    source $HOME/.bashrc'
	)
	for line in "${lines[@]}"; do
		printf 'export A=1\n%s\n' "$line" > "$HOME/.bash_profile"
		setup_target
		[[ $output == *"lines in ~/.bashrc "* ]] || { echo "not detected: $line"; false; }
		[[ $output == *"~/.bash_profile sources ~/.bashrc"* ]] || false
	done
}

@test "bash on macOS ignores a commented-out source of ~/.bashrc" {
	use_bash_on Darwin
	printf '# source ~/.bashrc\n  # . ~/.bashrc\n' > "$HOME/.bash_profile"
	setup_target
	[[ $output == *"lines in ~/.bash_profile "* ]] || false
}

@test "bash on macOS checks ~/.profile for a source of ~/.bashrc" {
	use_bash_on Darwin
	# The Ubuntu default ~/.profile
	printf 'if [ -n "$BASH_VERSION" ]; then\n    if [ -f "$HOME/.bashrc" ]; then\n\t. "$HOME/.bashrc"\n    fi\nfi\n' > "$HOME/.profile"
	setup_target
	[[ $output == *"lines in ~/.bashrc "* ]] || false
}

@test "another shell gets the command to use without the shell function" {
	use_test_home
	export SHELL=/usr/local/bin/fish
	setup_target
	[[ $output == *"supports bash and zsh"* ]] || false
	[[ $output == *'cd "$(shtl path ROUTE_NAME)"'* ]] || false
}

# Adding the lines

@test "setup without a terminal edits nothing" {
	use_bash_on Darwin
	echo 'export A=1' > "$HOME/.bash_profile"
	setup_target
	[[ $output == *"$INIT_LINE"* ]] || false
	[ "$(cat "$HOME/.bash_profile")" = 'export A=1' ]
}

@test "setup appends the lines after a blank line when you answer y" {
	use_bash_on Darwin
	printf 'export A=1\nsource ~/.bashrc\n' > "$HOME/.bash_profile"
	echo 'export B=1' > "$HOME/.bashrc"
	answer setup y
	[ "$(cat "$HOME/.bashrc")" = "$(printf 'export B=1\n\n%s\n%s' "$MARKER" "$INIT_LINE")" ]
	[ "$(cat "$HOME/.bash_profile")" = "$(printf 'export A=1\nsource ~/.bashrc')" ]
}

@test "setup makes the rc file when it doesn't exist" {
	use_test_home
	export SHELL=/bin/zsh
	answer setup y
	[ "$(cat "$HOME/.zshrc")" = "$(printf '%s\n%s' "$MARKER" "$INIT_LINE")" ]
}

@test "setup edits nothing when you answer n" {
	use_bash_on Linux
	echo 'export B=1' > "$HOME/.bashrc"
	answer setup n
	[[ $output == *"Skipped"* ]] || false
	[ "$(cat "$HOME/.bashrc")" = 'export B=1' ]
}

@test "setup finds the lines in the login file that sources ~/.bashrc" {
	use_bash_on Darwin
	printf 'source ~/.bashrc\n%s\n' "$INIT_LINE" > "$HOME/.bash_profile"
	touch "$HOME/.bashrc"
	setup_target
	[[ $output == *"already set up in ~/.bash_profile"* ]] || false
	[ ! -s "$HOME/.bashrc" ]
}

@test "setup doesn't add the lines twice" {
	use_bash_on Linux
	printf '%s\n%s\n' "$MARKER" "$INIT_LINE" > "$HOME/.bashrc"
	setup_target
	[[ $output == *"already set up in ~/.bashrc"* ]] || false
}

# Removing the lines

@test "unsetup removes the lines and the blank line before them" {
	use_bash_on Darwin
	printf 'export A=1\nsource ~/.bashrc\n' > "$HOME/.bash_profile"
	printf 'export B=1\n\n%s\n%s\nexport C=1\n' "$MARKER" "$INIT_LINE" > "$HOME/.bashrc"
	answer unsetup y
	[ "$(cat "$HOME/.bashrc")" = "$(printf 'export B=1\nexport C=1')" ]
}

@test "unsetup finds the lines in a file setup no longer picks" {
	use_bash_on Darwin
	# Added to ~/.bash_profile before it sourced ~/.bashrc
	printf 'source ~/.bashrc\n\n%s\n%s\n' "$MARKER" "$INIT_LINE" > "$HOME/.bash_profile"
	touch "$HOME/.bashrc"
	answer unsetup y
	[ "$(cat "$HOME/.bash_profile")" = 'source ~/.bashrc' ]
}

@test "unsetup keeps a symlinked rc file a symlink" {
	use_test_home
	export SHELL=/bin/zsh
	mkdir "$HOME/dotfiles"
	printf 'export A=1\n\n%s\n%s\n' "$MARKER" "$INIT_LINE" > "$HOME/dotfiles/zshrc"
	ln -s "$HOME/dotfiles/zshrc" "$HOME/.zshrc"
	answer unsetup y
	[ -L "$HOME/.zshrc" ]
	[ "$(cat "$HOME/dotfiles/zshrc")" = 'export A=1' ]
}

@test "unsetup without a terminal edits nothing" {
	use_bash_on Linux
	printf '%s\n%s\n' "$MARKER" "$INIT_LINE" > "$HOME/.bashrc"
	run shtl unsetup < /dev/null
	[ "$status" -eq 0 ]
	[ "$(cat "$HOME/.bashrc")" = "$(printf '%s\n%s' "$MARKER" "$INIT_LINE")" ]
}

@test "unsetup points out an init line it didn't add" {
	use_bash_on Linux
	echo 'eval "$(shtl init)"' > "$HOME/.bashrc"
	run shtl unsetup < /dev/null
	[[ $output == *"~/.bashrc runs 'shtl init'"* ]] || false
}

# Pointers to setup

@test "shtl ROUTE without the shell function points to setup" {
	shtl add a "$DIR_A"
	run --separate-stderr shtl a
	[[ $stderr == *"run: shtl setup"* ]] || false
}

@test "setup and unsetup work with a bad routes file and don't make one" {
	use_bash_on Linux
	run shtl setup < /dev/null
	[ "$status" -eq 0 ]
	[ ! -e "$ROUTES_FILE" ]
	mkdir -p "$(dirname "$ROUTES_FILE")"
	echo "not a routes file" > "$ROUTES_FILE"
	run shtl unsetup < /dev/null
	[ "$status" -eq 0 ]
}
