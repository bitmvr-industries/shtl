#!/usr/bin/env bats
# Each test sets its own SHELL, and rc file text and messages hold literal $ and ~
# shellcheck disable=SC2030,SC2031,SC2016,SC2088

# The Rust shtl's setup and unsetup. Which rc file each shell and OS uses is
# unit tested in src/setup.rs; these tests run the prompts and edit files.

load rust_helper

MARKER="# shtl: https://github.com/bitmvr-industries/shtl"
INIT_LINE='if command -v shtl >/dev/null; then eval "$(shtl init)"; fi'

use_zsh() {
	use_test_home
	export SHELL=/bin/zsh
	unset ZDOTDIR
}

use_bash() {
	use_test_home
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
	use_zsh
	setup_target
	[[ $output == *"lines in ~/.zshrc "* ]] || false
}

@test "zsh uses \$ZDOTDIR/.zshrc when ZDOTDIR is set" {
	use_zsh
	export ZDOTDIR="$HOME/.config/zsh"
	setup_target
	[[ $output == *"lines in ~/.config/zsh/.zshrc "* ]] || false
}

@test "bash uses the file for this OS" {
	use_bash
	setup_target
	if [[ $(uname) == Darwin ]]; then
		[[ $output == *"lines in ~/.bash_profile "* ]] || false
	else
		[[ $output == *"lines in ~/.bashrc "* ]] || false
	fi
}

@test "another shell gets the command to use without the shell function" {
	use_test_home
	export SHELL=/usr/local/bin/fish
	setup_target
	[ "$output" = 'shtl'"'"'s shell function supports bash and zsh. Without it, use: cd "$(shtl path ROUTE_NAME)"' ]
}

# Adding the lines

@test "setup without a terminal shows the lines and edits nothing" {
	use_zsh
	echo 'export A=1' > "$HOME/.zshrc"
	setup_target
	[ "${lines[0]}" = "shtl needs these lines in ~/.zshrc to change directories and tab-complete routes." ]
	[[ $output == *"    $MARKER"* && $output == *"    $INIT_LINE"* ]] || false
	[[ $output == *"Skipped. To set it up yourself, add those lines to the end of ~/.zshrc"* ]] || false
	[[ $output == *"(after compinit, so tab completion works), then open a new terminal."* ]] || false
	[ "$(cat "$HOME/.zshrc")" = 'export A=1' ]
}

@test "setup appends the lines after a blank line when you answer y" {
	use_zsh
	echo 'export A=1' > "$HOME/.zshrc"
	answer setup y
	[[ $output == *"Added. Open a new terminal, or run: source ~/.zshrc"* ]] || false
	[ "$(cat "$HOME/.zshrc")" = "$(printf 'export A=1\n\n%s\n%s' "$MARKER" "$INIT_LINE")" ]
}

@test "setup makes the rc file when it doesn't exist" {
	use_zsh
	answer setup Y
	[ "$(cat "$HOME/.zshrc")" = "$(printf '%s\n%s' "$MARKER" "$INIT_LINE")" ]
}

@test "setup edits nothing when you answer n" {
	use_zsh
	echo 'export B=1' > "$HOME/.zshrc"
	answer setup n
	[[ $output == *"Skipped"* ]] || false
	[ "$(cat "$HOME/.zshrc")" = 'export B=1' ]
}

@test "setup doesn't add the lines twice" {
	use_zsh
	printf 'eval "$(shtl init)"\n' > "$HOME/.zshrc"
	setup_target
	[ "$output" = "Shell integration already set up in ~/.zshrc" ]
}

@test "setup notes a symlinked rc file" {
	use_zsh
	mkdir "$HOME/dotfiles"
	touch "$HOME/dotfiles/zshrc"
	ln -s "$HOME/dotfiles/zshrc" "$HOME/.zshrc"
	setup_target
	[[ $output == *"Note: ~/.zshrc is a symlink to $HOME/dotfiles/zshrc. The change will be made in that file."* ]] || false
}

# Removing the lines

@test "unsetup removes the lines and the blank line before them" {
	use_bash
	printf 'export B=1\n\n%s\n%s\nexport C=1\n' "$MARKER" "$INIT_LINE" > "$HOME/.bashrc"
	answer unsetup y
	[[ $output == *"~/.bashrc has shtl's shell integration lines."* && $output == *"Removed."* ]] || false
	[ "$(cat "$HOME/.bashrc")" = "$(printf 'export B=1\nexport C=1')" ]
}

@test "unsetup finds the lines in every bash rc file" {
	use_bash
	printf 'source ~/.bashrc\n\n%s\n%s\n' "$MARKER" "$INIT_LINE" > "$HOME/.bash_profile"
	touch "$HOME/.bashrc"
	answer unsetup y
	[ "$(cat "$HOME/.bash_profile")" = 'source ~/.bashrc' ]
}

@test "unsetup keeps a symlinked rc file a symlink" {
	use_zsh
	mkdir "$HOME/dotfiles"
	printf 'export A=1\n\n%s\n%s\n' "$MARKER" "$INIT_LINE" > "$HOME/dotfiles/zshrc"
	ln -s "$HOME/dotfiles/zshrc" "$HOME/.zshrc"
	answer unsetup y
	[ -L "$HOME/.zshrc" ]
	[ "$(cat "$HOME/dotfiles/zshrc")" = 'export A=1' ]
}

@test "unsetup without a terminal edits nothing" {
	use_bash
	printf '%s\n%s\n' "$MARKER" "$INIT_LINE" > "$HOME/.bashrc"
	run shtl unsetup < /dev/null
	[ "$status" -eq 0 ]
	[[ $output == *"Kept. The line is guarded, so it does nothing while shtl isn't installed."* ]] || false
	[ "$(cat "$HOME/.bashrc")" = "$(printf '%s\n%s' "$MARKER" "$INIT_LINE")" ]
}

@test "unsetup points out an init line it didn't add" {
	use_bash
	echo 'eval "$(shtl init)"' > "$HOME/.bashrc"
	run shtl unsetup < /dev/null
	[ "$output" = "~/.bashrc runs 'shtl init'. setup didn't add that line, so remove it yourself." ]
}

@test "unsetup with no lines says so" {
	use_zsh
	run shtl unsetup < /dev/null
	[ "$output" = "No shtl lines in your rc files" ]
}

@test "setup and unsetup work with a bad routes file and don't make one" {
	use_zsh
	run shtl setup < /dev/null
	[ "$status" -eq 0 ]
	[ ! -e "$ROUTES_FILE" ]
	mkdir -p "$(dirname "$ROUTES_FILE")"
	echo "not a routes file" > "$ROUTES_FILE"
	run shtl setup < /dev/null
	[ "$status" -eq 0 ]
	run shtl unsetup < /dev/null
	[ "$status" -eq 0 ]
}
