#!/usr/bin/env bash

# Route List (XDG Base Directory spec)
readonly CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/shtl"
readonly ROUTES_FILE="$CONFIG_DIR/routes"

# First line of the routes file. Each route below it is NAME[FLAGS]:PATH,
# e.g. work[]:/Users/me/work or nas[persist]:/Volumes/nas. FLAGS is a
# comma-separated list. PATH comes last so it can contain anything, colons included.
readonly ROUTES_HEADER="# shtl routes v2"

# Replaced with the contents of VERSION by `make build`
readonly SHTL_VERSION="__SHTL_VERSION__"

# Subcommands. Route names can't use these, and the shell function from
# `shtl init` passes them straight through to the script.
readonly SHTL_COMMANDS="add update remove rm list ls clean persist path init help version"


# Prints "shtl [LEVEL] message" to stderr. The message is printed as-is, so
# backslashes in route names or paths aren't treated as escapes.
shtl_log() {
	local log_level="${1}"
	local msg="${2}"
	printf '%s %-7s %s\n' "$(basename "${0}")" "[${log_level}]" "${msg}" >&2
}

shtl_validate_arguments(){
	if [[ $# -eq 0 ]]; then
		shtl_log "ERROR" "Please provide a route name"
		exit 1
	fi
}

shtl_init(){
	local firstLine=""
	mkdir -p "$CONFIG_DIR"
	if [[ ! -f $ROUTES_FILE ]]; then
		echo "$ROUTES_HEADER" > "$ROUTES_FILE"
		return 0
	fi
	IFS='' read -r firstLine < "$ROUTES_FILE"
	if [[ $firstLine == "$ROUTES_HEADER" ]]; then
		return 0
	fi
	if [[ $firstLine == "# shtl routes "* ]]; then
		shtl_log "ERROR" "${ROUTES_FILE} was written by a newer version of shtl (${firstLine#\# shtl routes }). Please upgrade shtl"
		exit 1
	fi
	shtl_migrate_v1_routes || exit 1
}

# Converts the original NAME:PATH[:persist] format, read exactly the way
# older versions read it, and keeps a copy of the original file.
shtl_migrate_v1_routes(){
	local entry name path flags
	local invalid=() converted=()
	while IFS='' read -r entry || [[ -n "$entry" ]]; do
		[[ -z ${entry//[[:space:]]/} ]] && continue
		name="${entry%%:*}"
		if [[ $entry != *:* ]] || ! shtl_is_valid_name_format "$name"; then
			invalid+=("$entry")
			continue
		fi
		path="${entry#*:}"
		flags=""
		if [[ $path == *:persist ]]; then
			path="${path%:persist}"
			flags="persist"
		fi
		converted+=("$(shtl_format_entry "$name" "$flags" "$path")")
	done < "$ROUTES_FILE"

	if [[ ${#invalid[@]} -gt 0 ]]; then
		shtl_log "ERROR" "Could not update ${ROUTES_FILE} to the new format. Route names can't contain \"[\" or \"]\" or start with \"#\". Rename or remove these entries, then run shtl again: $(printf '\n  %s' "${invalid[@]}")"
		return 1
	fi

	# Older versions created an empty file on first run; nothing to convert
	if [[ ${#converted[@]} -eq 0 ]]; then
		echo "$ROUTES_HEADER" > "$ROUTES_FILE"
		return 0
	fi

	cp "$ROUTES_FILE" "$ROUTES_FILE.v1.bak" || return 1
	printf '%s\n' "${converted[@]}" > "$ROUTES_FILE.tmp" && mv "$ROUTES_FILE.tmp" "$ROUTES_FILE"
	shtl_refresh_routes
	shtl_log "INFO" "Updated ${ROUTES_FILE} to the new format. The original is saved as ${ROUTES_FILE}.v1.bak"
}

# Rewrites the routes file: header first, then routes sorted by name
shtl_refresh_routes() {
	{ echo "$ROUTES_HEADER"; shtl_get_entries | sort --ignore-case -t '[' -k1,1; } > "$ROUTES_FILE.tmp" && mv "$ROUTES_FILE.tmp" "$ROUTES_FILE"
}

# Prints every route entry, skipping the header, comments and blank lines
shtl_get_entries() {
	awk '!/^#/ && /[^[:space:]]/' "$ROUTES_FILE"
}

shtl_usage() {
	echo ""
	echo "$(basename "$0") - Help"
	echo ""
	echo "  Usage: shtl ROUTE_NAME"
	echo "         shtl COMMAND [ARGS]"
	echo ""
	echo "    ROUTE_NAME                      Jump to a route (needs the shell function, see init)"
	echo "    add NAME [PATH] [-p|--persist]  Add a route. PATH must be absolute and defaults to the current directory"
	echo "                                    --persist keeps the route even if its directory doesn't exist (clean skips it)"
	echo "    update NAME [PATH]              Point a route at a new absolute path. PATH defaults to the current directory"
	echo "    remove | rm NAME                Remove a route"
	echo "    list | ls                       List routes"
	echo "    clean                           Interactively remove routes whose directories no longer exist"
	echo "    persist NAME                    Toggle whether clean skips a route"
	echo "    path NAME                       Print a route's path (e.g. cp file \"\$(shtl path work)\")"
	echo "    init                            Print the shell function. Add to your ~/.zshrc or ~/.bashrc: eval \"\$(shtl init)\""
	echo "    help                            Display this information"
	echo "    version                         Print the shtl version"
	echo ""
}

# Names are matched as literal strings, not regexes, so "a.b" can't match "axb"
shtl_get_route_entry() {
	SHTL_ROUTE_NAME="$1" awk 'index($0, ENVIRON["SHTL_ROUTE_NAME"] "[") == 1' "$ROUTES_FILE"
}

shtl_remove_route_entry() {
	SHTL_ROUTE_NAME="$1" awk 'index($0, ENVIRON["SHTL_ROUTE_NAME"] "[") != 1' "$ROUTES_FILE" > "$ROUTES_FILE.tmp" && mv "$ROUTES_FILE.tmp" "$ROUTES_FILE"
}

# Entry helpers. An entry is NAME[FLAGS]:PATH (see ROUTES_HEADER).
shtl_format_entry() {
	echo "${1}[${2}]:${3}"
}

shtl_get_entry_name() {
	echo "${1%%\[*}"
}

shtl_get_entry_flags() {
	local flags="${1%%:*}"
	flags="${flags#*\[}"
	echo "${flags%\]}"
}

shtl_get_entry_path() {
	echo "${1#*:}"
}

shtl_entry_is_persistent() {
	[[ ",$(shtl_get_entry_flags "$1")," == *,persist,* ]]
}

shtl_get_route() {
	local route
	route=$(shtl_get_route_entry "$1")
	shtl_get_entry_path "$route"
}

shtl_get_route_names(){
	local entry
	while IFS='' read -r entry; do
		shtl_get_entry_name "$entry"
	done < <(shtl_get_entries)
}

shtl_get_current_path() {
	pwd
}

# Removes ".", ".." and extra slashes from an absolute path, without
# touching the filesystem: the directory may not exist yet (--persist), and
# symlinks are kept as typed, the same way pwd reports them
shtl_normalize_path() {
	local path="$1" part
	local parts=() kept=()
	IFS='/' read -r -a parts <<< "$path"
	for part in "${parts[@]}"; do
		case $part in
			''|.) ;;
			..) [[ ${#kept[@]} -gt 0 ]] && unset 'kept[${#kept[@]}-1]' ;;
			*) kept+=("$part") ;;
		esac
	done
	(IFS='/'; printf '/%s\n' "${kept[*]}")
}

shtl_has_routes() {
	[[ -n $(shtl_get_entries) ]]
}

# Prints NAME  PATH columns, marking persistent routes
shtl_list_routes() {
	local entry name i width=0
	local names=() paths=() marks=()
	if ! shtl_has_routes; then
		shtl_log "INFO" "No routes yet. Add one with: shtl add NAME [PATH]"
		return 0
	fi
	while IFS='' read -r entry; do
		name="$(shtl_get_entry_name "$entry")"
		names+=("$name")
		paths+=("$(shtl_get_entry_path "$entry")")
		if shtl_entry_is_persistent "$entry"; then
			marks+=("  (persist)")
		else
			marks+=("")
		fi
		(( ${#name} > width )) && width=${#name}
	done < <(shtl_get_entries)
	for i in "${!names[@]}"; do
		printf '%-*s  %s%s\n' "$width" "${names[i]}" "${paths[i]}" "${marks[i]}"
	done
	# Routes added before a command of the same name existed can't be jumped to
	for name in "${names[@]}"; do
		if shtl_is_command "$name"; then
			shtl_log "WARN" "Route \"${name}\" has the same name as a shtl command, so shtl ${name} runs the command. Use: cd \"\$(shtl path ${name})\", or remove it and add it under a new name"
		fi
	done
}

shtl_generate_route() {
	local currentDir
	currentDir="$(shtl_get_current_path)"
	local routeName="$1"
	local providedPath="$2"
	local persist="$3"
	local route
	route="$(shtl_normalize_path "${providedPath:-$currentDir}")"
	shtl_format_entry "$routeName" "$persist" "$route"
}

shtl_route_name_exists(){
	[[ -n $(shtl_get_route_entry "$1") ]]
}

shtl_is_command(){
	[[ " $SHTL_COMMANDS " == *" $1 "* ]]
}

# Characters the routes file format reserves: ":" and "[ ]" delimit an
# entry and "#" starts a comment
shtl_is_valid_name_format(){
	[[ -n $1 && $1 != *:* && $1 != *'['* && $1 != *']'* && $1 != '#'* ]]
}

# A given PATH must be absolute. Leaving it out uses the current directory.
shtl_validate_path(){
	if [[ -n $1 && $1 != /* ]]; then
		shtl_log "ERROR" "\"${1}\" is not an absolute path. Use a full path starting with \"/\", or leave PATH out to use the current directory"
		return 1
	fi
}

shtl_add_route(){
	# Names also can't start with "-" (flags) or be a subcommand
	if [[ $1 == -* ]] || ! shtl_is_valid_name_format "$1" || shtl_is_command "$1"; then
		shtl_log "ERROR" "Route names can't start with \"-\" or \"#\", contain \":\", \"[\" or \"]\", or be a shtl command (${SHTL_COMMANDS// /, })"
		return 1
	fi
	if shtl_route_name_exists "$1"; then
		shtl_log "ERROR" "It appears this route already exists in your routes"
		return 1
	fi	
	shtl_validate_path "$2" || return 1
	shtl_generate_route "$@" >> "$ROUTES_FILE" && shtl_refresh_routes
}

shtl_delete_route() {
	local routeName="$1"
	if shtl_route_name_exists "$routeName"; then
		shtl_remove_route_entry "$routeName"
	else
		shtl_log "ERROR" "Could not remove route \"${routeName}\". The route does not exist"
		return 1
	fi
}

# Points an existing route at a new path, keeping its flags
shtl_update_route() {
	local routeName="$1"
	local providedPath="$2"
	local entry route
	if ! shtl_route_name_exists "$routeName"; then
		shtl_log "ERROR" "Could not update route \"${routeName}\". The route does not exist"
		return 1
	fi
	shtl_validate_path "$providedPath" || return 1
	entry="$(shtl_get_route_entry "$routeName")"
	route="$(shtl_normalize_path "${providedPath:-$(shtl_get_current_path)}")"
	shtl_remove_route_entry "$routeName"
	shtl_format_entry "$routeName" "$(shtl_get_entry_flags "$entry")" "$route" >> "$ROUTES_FILE" && shtl_refresh_routes
	shtl_log "INFO" "Route \"${routeName}\" now points to ${route}"
}

# Draws the clean checklist. Reads names, paths, selected, cursor and width
# from the calling shtl_clean_routes (bash locals are dynamically scoped).
shtl_draw_clean_list() {
	local i mark pointer count=0
	for i in "${!names[@]}"; do
		mark=" "
		if [[ ${selected[i]} -eq 1 ]]; then
			mark="x"
			count=$((count + 1))
		fi
		pointer=" "
		[[ $i -eq $cursor ]] && pointer=">"
		printf '\033[2K%s [%s] %-*s  %s\n' "$pointer" "$mark" "$width" "${names[i]}" "${paths[i]}" >&2
	done
	printf '\033[2K\n\033[2K%s selected\n' "$count" >&2
}

shtl_clean_routes() {
	local names=() paths=() selected=()
	local entry path name key rest i next
	local cursor=0 width=0 removed=0

	if ! shtl_has_routes; then
		shtl_log "INFO" "No routes to clean. Add one with: shtl add NAME [PATH]"
		return 0
	fi

	while IFS='' read -r entry; do
		shtl_entry_is_persistent "$entry" && continue
		path="$(shtl_get_entry_path "$entry")"
		[[ -d $path ]] && continue
		names+=("$(shtl_get_entry_name "$entry")")
		paths+=("$path")
		selected+=(1)
	done < <(shtl_get_entries)

	if [[ ${#names[@]} -eq 0 ]]; then
		shtl_log "INFO" "All routes point to existing directories"
		return 0
	fi

	if [[ ! -t 0 || ! -t 2 ]]; then
		shtl_log "ERROR" "Clean needs an interactive terminal"
		return 1
	fi

	for name in "${names[@]}"; do
		(( ${#name} > width )) && width=${#name}
	done

	# Hide the cursor while drawing; always restore it and echo on the way out
	trap 'printf "\033[?25h" >&2; stty echo 2>/dev/null' EXIT
	trap 'exit 130' INT
	printf '\033[?25l' >&2

	printf '\nshtl clean — routes whose directories no longer exist\n\n' >&2
	printf '  ↑/↓ move   space toggle   a all   enter remove   q cancel\n\n' >&2
	shtl_draw_clean_list

	while true; do
		IFS= read -rsn1 key
		if [[ $key == $'\033' ]]; then
			IFS= read -rsn2 -t 1 rest
			key+="$rest"
		fi
		case $key in
			$'\033[A'|$'\033OA'|k)
				(( cursor > 0 )) && cursor=$((cursor - 1))
				;;
			$'\033[B'|$'\033OB'|j)
				(( cursor < ${#names[@]} - 1 )) && cursor=$((cursor + 1))
				;;
			' ')
				selected[cursor]=$((1 - selected[cursor]))
				;;
			a)
				# Select all, or deselect all if everything is already selected
				next=0
				for i in "${!selected[@]}"; do
					[[ ${selected[i]} -eq 0 ]] && next=1
				done
				for i in "${!selected[@]}"; do
					selected[i]=$next
				done
				;;
			'')
				break
				;;
			q)
				shtl_log "INFO" "Clean cancelled. No routes were removed"
				return 0
				;;
		esac
		printf '\033[%dA' $(( ${#names[@]} + 2 )) >&2
		shtl_draw_clean_list
	done

	for i in "${!names[@]}"; do
		if [[ ${selected[i]} -eq 1 ]]; then
			shtl_delete_route "${names[i]}"
			removed=$((removed + 1))
		fi
	done
	shtl_log "INFO" "Removed ${removed} route(s)"
}

shtl_toggle_persist() {
	local routeName="$1"
	local entry newEntry flags
	if ! shtl_route_name_exists "$routeName"; then
		shtl_log "ERROR" "Could not persist route \"${routeName}\". The route does not exist"
		return 1
	fi
	entry="$(shtl_get_route_entry "$routeName")"
	flags="$(shtl_get_entry_flags "$entry")"
	if shtl_entry_is_persistent "$entry"; then
		# Drop "persist" from the comma-separated flags, keeping any others
		flags=",${flags},"
		flags="${flags//,persist,/,}"
		flags="${flags#,}"
		flags="${flags%,}"
	else
		flags="${flags:+${flags},}persist"
	fi
	newEntry="$(shtl_format_entry "$routeName" "$flags" "$(shtl_get_entry_path "$entry")")"
	shtl_remove_route_entry "$routeName"
	echo "$newEntry" >> "$ROUTES_FILE" && shtl_refresh_routes
	if shtl_entry_is_persistent "$newEntry"; then
		shtl_log "INFO" "Route \"${routeName}\" is now persistent. Clean will skip it"
	else
		shtl_log "INFO" "Route \"${routeName}\" is no longer persistent"
	fi
}

# Prints only the route's path, for the shell function and for use in scripts
shtl_print_path(){
	local routeName="$1"
	local path
	if ! shtl_route_name_exists "$routeName"; then
		shtl_log "ERROR" "Route \"${routeName}\" does not exist"
		return 1
	fi
	path="$(shtl_get_route "$routeName")"
	if [[ ! -d $path ]]; then
		shtl_log "ERROR" "Route \"${routeName}\" points to ${path}, which doesn't exist"
		return 1
	fi
	echo "$path"
}

# A script can't change its parent shell's directory. Without the shell
# function from `shtl init`, print the path and explain how to set it up.
shtl_route(){
	shtl_print_path "$1" || return 1
	shtl_log "WARN" "shtl can't change directory without its shell function. Add this to your ~/.zshrc or ~/.bashrc: eval \"\$(shtl init)\""
}

# Prints the shell function and tab completion. Works in bash and zsh:
# eval "$(shtl init)"
shtl_print_init(){
	local commandPattern="${SHTL_COMMANDS// /|}"
	sed -e "s/__SHTL_COMMAND_PATTERN__/${commandPattern}/" -e "s/__SHTL_COMMANDS__/${SHTL_COMMANDS}/" <<'EOF'
shtl() {
	case "$1" in
		""|-*|__SHTL_COMMAND_PATTERN__) command shtl "$@" ;;
		*)
			local dest
			dest="$(command shtl path "$1")" && cd -- "$dest"
			;;
	esac
}

if [ -n "$ZSH_VERSION" ]; then
	_shtl() {
		local -a routes subcommands
		routes=(${(f)"$(command shtl list --names)"})
		subcommands=(__SHTL_COMMANDS__)
		if (( CURRENT == 2 )); then
			compadd -a subcommands
			compadd -a routes
		elif (( CURRENT == 3 )); then
			case "${words[2]}" in
				remove|rm|update|persist|path) compadd -a routes ;;
			esac
		elif (( CURRENT == 4 )) && [[ "${words[2]}" == add || "${words[2]}" == update ]]; then
			_files -/
		fi
	}
	if (( $+functions[compdef] )); then
		compdef _shtl shtl
	fi
elif [ -n "$BASH_VERSION" ]; then
	_shtl() {
		local cur="${COMP_WORDS[COMP_CWORD]}"
		local words=""
		if [ "$COMP_CWORD" -eq 1 ]; then
			words="__SHTL_COMMANDS__ $(command shtl list --names)"
		elif [ "$COMP_CWORD" -eq 2 ]; then
			case "${COMP_WORDS[1]}" in
				remove|rm|update|persist|path) words="$(command shtl list --names)" ;;
			esac
		elif [ "$COMP_CWORD" -eq 3 ] && { [ "${COMP_WORDS[1]}" = add ] || [ "${COMP_WORDS[1]}" = update ]; }; then
			COMPREPLY=($(compgen -d -- "$cur"))
			return
		fi
		COMPREPLY=($(compgen -W "$words" -- "$cur"))
	}
	complete -F _shtl shtl
fi
EOF
}

shtl_version(){
	# Running from source (unbuilt): read VERSION from the repo root
	if [[ $SHTL_VERSION == __* ]]; then
		cat "$(dirname "$0")/../VERSION"
	else
		echo "$SHTL_VERSION"
	fi
}
