#!/usr/bin/env bash

# Offers to add or remove shtl's shell integration in the user's rc file.
# Used by `make install` and `make uninstall`. Only edits the rc file after
# the user says yes, and never prompts when not run from a terminal.

readonly MARKER="# shtl: https://github.com/bitmvr-industries/shtl"
# shellcheck disable=SC2016 # written to the rc file literally, expanded there
readonly INIT_LINE='if command -v shtl >/dev/null; then eval "$(shtl init)"; fi'

setup_rc_file() {
	case "$SHELL" in
		*/zsh)
			echo "${ZDOTDIR:-$HOME}/.zshrc"
			;;
		*/bash)
			# macOS terminals open login shells, which read .bash_profile
			if [[ $(uname) == Darwin ]]; then
				echo "$HOME/.bash_profile"
			else
				echo "$HOME/.bashrc"
			fi
			;;
	esac
}

setup_confirm() {
	local reply
	[[ -t 0 ]] || return 1
	read -r -p "$1 [y/N] " reply
	[[ $reply == [yY] || $reply == [yY][eE][sS] ]]
}

setup_symlink_note() {
	local rc="$1"
	if [[ -L $rc ]]; then
		echo "Note: $rc is a symlink to $(readlink "$rc"). The change will be made in that file."
	fi
}

setup_install() {
	local rc
	rc="$(setup_rc_file)"

	if [[ -z $rc ]]; then
		echo ""
		echo "shtl's shell integration supports bash and zsh. Without it, use: cd \"\$(shtl path ROUTE_NAME)\""
		return 0
	fi

	if grep -qs 'shtl init' "$rc"; then
		echo "Shell integration already set up in $rc"
		return 0
	fi

	echo ""
	echo "shtl needs these lines in $rc to change directories and tab-complete routes:"
	echo ""
	echo "    $MARKER"
	echo "    $INIT_LINE"
	echo ""
	setup_symlink_note "$rc"

	if setup_confirm "Append them to the end of $rc?"; then
		# Separate from existing content with a blank line, unless the file is empty
		if [[ -s $rc ]]; then
			echo "" >> "$rc"
		fi
		printf '%s\n%s\n' "$MARKER" "$INIT_LINE" >> "$rc"
		echo "Added. Open a new terminal, or run: source $rc"
	else
		echo "Skipped. To set it up yourself, add those lines to the end of $rc"
		if [[ $SHELL == */zsh ]]; then
			echo "(after compinit, so tab completion works), then open a new terminal."
		else
			echo "then open a new terminal."
		fi
	fi
}

setup_uninstall() {
	local rc tmp
	rc="$(setup_rc_file)"

	if [[ -z $rc || ! -f $rc ]]; then
		return 0
	fi

	if grep -qxF "$MARKER" "$rc"; then
		echo ""
		echo "$rc has shtl's shell integration lines:"
		echo ""
		echo "    $MARKER"
		echo "    $INIT_LINE"
		echo ""
		setup_symlink_note "$rc"
		if setup_confirm "Remove them from $rc?"; then
			tmp="$(mktemp)"
			# Drop the marker, the init line after it, and the blank line we added before it
			awk -v marker="$MARKER" -v init="$INIT_LINE" '
				{ lines[NR] = $0 }
				END {
					for (i = 1; i <= NR; i++) {
						if (lines[i] == marker && lines[i + 1] == init) {
							skip[i] = skip[i + 1] = 1
							if (i > 1 && lines[i - 1] == "") skip[i - 1] = 1
						}
					}
					for (i = 1; i <= NR; i++) if (!skip[i]) print lines[i]
				}
			' "$rc" > "$tmp"
			# Write back in place so symlinks and permissions are kept
			cat "$tmp" > "$rc"
			rm -f "$tmp"
			echo "Removed."
		else
			echo "Kept. The line is guarded, so it does nothing while shtl isn't installed."
		fi
	elif grep -qs 'shtl init' "$rc"; then
		echo ""
		echo "$rc still runs 'shtl init'. That line wasn't added by make install, so remove it yourself."
	fi
}

case "$1" in
	install) setup_install ;;
	uninstall) setup_uninstall ;;
	*)
		echo "Usage: $0 install|uninstall" >&2
		exit 1
		;;
esac
