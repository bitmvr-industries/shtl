#!/usr/bin/env bats
# Each test sets its own SHELL, and rc file text and messages hold literal $ and ~
# shellcheck disable=SC2030,SC2031,SC2016,SC2088

# shtl's setup and unsetup. Which rc file each shell and OS uses is
# unit tested in src/setup.rs; these tests run the prompts and edit files.

load test_helper

MARKER="# shtl: https://github.com/bitmvr-industries/shtl"
PLACEHOLDERS='shtl() { unset -f shtl; eval "$(command shtl init 2>/dev/null)"; shtl "$@"; }; _shtl() { local s; s="$(command shtl init 2>/dev/null)" || return; unset -f _shtl; eval "$s"; _shtl "$@"; }'
BASH_LINE="$PLACEHOLDERS; complete -F _shtl shtl"
ZSH_LINE="$PLACEHOLDERS; if (( \$+functions[compdef] )); then compdef _shtl shtl; fi"

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
	[[ $output == *"    $MARKER"* && $output == *"    $ZSH_LINE"* ]] || false
	[[ $output == *"Skipped. To set it up yourself, add those lines to the end of ~/.zshrc"* ]] || false
	[[ $output == *"(after compinit, so tab completion works), then open a new terminal."* ]] || false
	[ "$(cat "$HOME/.zshrc")" = 'export A=1' ]
}

@test "setup appends the lines after a blank line when you answer y" {
	use_zsh
	echo 'export A=1' > "$HOME/.zshrc"
	answer setup y
	[[ $output == *"Added. Open a new terminal, or run: source ~/.zshrc"* ]] || false
	[ "$(cat "$HOME/.zshrc")" = "$(printf 'export A=1\n\n%s\n%s' "$MARKER" "$ZSH_LINE")" ]
}

@test "setup makes the rc file when it doesn't exist" {
	use_zsh
	answer setup Y
	[ "$(cat "$HOME/.zshrc")" = "$(printf '%s\n%s' "$MARKER" "$ZSH_LINE")" ]
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

# Login shells

# Writes the order of the stock Ubuntu ~/.profile: it reads ~/.bashrc first and
# adds ~/.local/bin to PATH after that
use_ubuntu_profile() {
	use_bash
	cat > "$HOME/.profile" <<-'EOF'
		if [ -n "$BASH_VERSION" ]; then
		    if [ -f "$HOME/.bashrc" ]; then
		        . "$HOME/.bashrc"
		    fi
		fi
		if [ -d "$HOME/.local/bin" ] ; then
		    PATH="$HOME/.local/bin:$PATH"
		fi
	EOF
	touch "$HOME/.bashrc"
}

# Runs commands in a new login shell with a minimal PATH
login_shell() {
	run env -i HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" PATH=/usr/bin:/bin /bin/bash -l -c "$1"
}

# Puts a copy of shtl in a directory
install_shtl() {
	mkdir -p "$1"
	cp "$(command -v shtl)" "$1/shtl"
}

# A PATH change like Homebrew's shellenv, for a binary in ~/brew/bin
BREW_PATH='PATH="$HOME/brew/bin:$PATH"'

# Starts the shell command in $1, types "shtl wo<Tab><Enter>" as the first use
# of shtl and prints the directory it ended up in
first_tab() {
	command -v expect > /dev/null || skip "expect not installed"
	export TAB_SHELL="$1"
	run expect -c '
		set timeout 5
		log_user 0
		spawn env -i HOME=$env(HOME) XDG_CONFIG_HOME=$env(XDG_CONFIG_HOME) TERM=dumb PATH=/usr/bin:/bin {*}$env(TAB_SHELL)
		send "PS1=\"> \"\r"
		expect "> "
		send "shtl wo\t"
		sleep 0.5
		send "\r"
		expect "> "
		send "echo @@\$PWD@@\r"
		expect -re {@@(/[^@]*)@@}
		puts $expect_out(1,string)
		send "exit\r"'
}

@test "the first use at login changes directory on stock Ubuntu" {
	use_ubuntu_profile
	install_shtl "$HOME/.local/bin"
	add_route work "$DIR_A"
	answer setup y
	login_shell 'shtl work && pwd'
	[ "$output" = "$DIR_A" ]
}

@test "the first use at login changes directory when ~/.profile sets PATH after the rc file" {
	use_ubuntu_profile
	install_shtl "$HOME/brew/bin"
	add_route work "$DIR_A"
	answer setup y
	echo "$BREW_PATH" >> "$HOME/.profile"
	login_shell 'shtl work && pwd'
	[ "$output" = "$DIR_A" ]
}

@test "the first use at login changes directory when the rc file sets PATH below the lines" {
	use_ubuntu_profile
	install_shtl "$HOME/brew/bin"
	add_route work "$DIR_A"
	answer setup y
	echo "$BREW_PATH" >> "$HOME/.bashrc"
	login_shell 'shtl work && pwd'
	[ "$output" = "$DIR_A" ]
}

@test "the first use in zsh changes directory when the rc file sets PATH below the lines" {
	command -v zsh > /dev/null || skip "zsh not installed"
	use_zsh
	install_shtl "$HOME/brew/bin"
	add_route work "$DIR_A"
	answer setup y
	echo "$BREW_PATH" >> "$HOME/.zshrc"
	# No compinit in this rc file, so this also shows the lines don't need it
	run env -i HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" TERM=dumb PATH=/usr/bin:/bin "$(command -v zsh)" -i -c 'shtl work && pwd'
	[ "$output" = "$DIR_A" ]
}

@test "the first use passes on the status of shtl" {
	use_ubuntu_profile
	install_shtl "$HOME/brew/bin"
	answer setup y
	echo "$BREW_PATH" >> "$HOME/.bashrc"
	login_shell 'shtl nope; echo "status=$?"'
	[[ $output == *"status=1" ]] || false
}

@test "the function still works after the rc file is read again" {
	use_ubuntu_profile
	install_shtl "$HOME/brew/bin"
	add_route work "$DIR_A"
	answer setup y
	echo "$BREW_PATH" >> "$HOME/.bashrc"
	login_shell '. ~/.bashrc; shtl work; cd /; . ~/.bashrc; shtl work && pwd'
	[ "$output" = "$DIR_A" ]
}

@test "the lines are quiet at login and shtl reports once when it isn't installed" {
	use_ubuntu_profile
	answer setup y
	login_shell 'echo loaded; shtl version; echo "status=$?"'
	[ "${#lines[@]}" -eq 3 ]
	[ "${lines[0]}" = loaded ]
	[[ ${lines[1]} == *"command not found" ]] || false
	[ "${lines[2]}" = "status=127" ]
}

@test "tab completion stays quiet every time when shtl isn't installed" {
	use_ubuntu_profile
	answer setup y
	login_shell 'COMP_WORDS=(shtl ""); COMP_CWORD=1; _shtl; _shtl; type -t _shtl'
	[ "$output" = function ]
}

@test "the first Tab in a new bash completes a route" {
	use_ubuntu_profile
	install_shtl "$HOME/brew/bin"
	add_route work "$DIR_A"
	answer setup y
	echo "$BREW_PATH" >> "$HOME/.profile"
	first_tab "/bin/bash -l -i"
	[ "$status" -eq 0 ]
	[ "$output" = "$DIR_A" ]
}

@test "the first Tab in a new zsh completes a route" {
	command -v zsh > /dev/null || skip "zsh not installed"
	use_zsh
	install_shtl "$HOME/brew/bin"
	add_route work "$DIR_A"
	printf 'autoload -Uz compinit; compinit -u\nunsetopt beep\n' > "$HOME/.zshrc"
	answer setup y
	echo "$BREW_PATH" >> "$HOME/.zshrc"
	first_tab "$(command -v zsh) -i"
	[ "$status" -eq 0 ]
	[ "$output" = "$DIR_A" ]
}

# The docs

@test "the README shows the lines for bash and zsh" {
	grep -qF "$BASH_LINE" "$REPO_DIR/README.md"
	grep -qF "$ZSH_LINE" "$REPO_DIR/README.md"
}

@test "the man page shows the lines for bash and zsh" {
	# The man page writes a hyphen as \-
	sed 's/\\-/-/g' "$REPO_DIR/man/shtl.1" | grep -qF "$BASH_LINE"
	sed 's/\\-/-/g' "$REPO_DIR/man/shtl.1" | grep -qF "$ZSH_LINE"
}

# Removing the lines

@test "unsetup removes the guarded line of older versions" {
	use_bash
	printf 'export B=1\n\n%s\n%s\n' "$MARKER" 'if command -v shtl >/dev/null; then eval "$(shtl init)"; fi' > "$HOME/.bashrc"
	answer unsetup y
	[ "$(cat "$HOME/.bashrc")" = 'export B=1' ]
}

@test "unsetup removes the lines and the blank line before them" {
	use_bash
	printf 'export B=1\n\n%s\n%s\nexport C=1\n' "$MARKER" "$BASH_LINE" > "$HOME/.bashrc"
	answer unsetup y
	[[ $output == *"~/.bashrc has shtl's shell integration lines."* && $output == *"Removed."* ]] || false
	[ "$(cat "$HOME/.bashrc")" = "$(printf 'export B=1\nexport C=1')" ]
}

@test "unsetup finds the lines in every bash rc file" {
	use_bash
	printf 'source ~/.bashrc\n\n%s\n%s\n' "$MARKER" "$BASH_LINE" > "$HOME/.bash_profile"
	touch "$HOME/.bashrc"
	answer unsetup y
	[ "$(cat "$HOME/.bash_profile")" = 'source ~/.bashrc' ]
}

@test "unsetup keeps a symlinked rc file a symlink" {
	use_zsh
	mkdir "$HOME/dotfiles"
	printf 'export A=1\n\n%s\n%s\n' "$MARKER" "$ZSH_LINE" > "$HOME/dotfiles/zshrc"
	ln -s "$HOME/dotfiles/zshrc" "$HOME/.zshrc"
	answer unsetup y
	[ -L "$HOME/.zshrc" ]
	[ "$(cat "$HOME/dotfiles/zshrc")" = 'export A=1' ]
}

@test "unsetup without a terminal edits nothing" {
	use_bash
	printf '%s\n%s\n' "$MARKER" "$BASH_LINE" > "$HOME/.bashrc"
	run shtl unsetup < /dev/null
	[ "$status" -eq 0 ]
	[[ $output == *"Kept. The line is safe while shtl isn't installed: it runs shtl only when you use it."* ]] || false
	[ "$(cat "$HOME/.bashrc")" = "$(printf '%s\n%s' "$MARKER" "$BASH_LINE")" ]
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
