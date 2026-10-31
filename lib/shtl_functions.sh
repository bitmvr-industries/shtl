#!/usr/bin/env bash

# Route List (XDG Base Directory spec)
readonly CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/shtl"
readonly ROUTES_FILE="$CONFIG_DIR/routes"

# First line of the routes file. Each route below it is NAME[FLAGS]:PATH,
# e.g. work[]:/Users/me/work or nas[persist]:/Volumes/nas. FLAGS is a
# comma-separated list. PATH comes last so it can contain anything, colons included.
# The format version matches shtl's major version. Bump both together.
readonly ROUTES_HEADER="# shtl routes v1"

# Replaced with the contents of VERSION by `make build`
readonly SHTL_VERSION="__SHTL_VERSION__"

# Subcommands. Route names can't use these, and the shell function from
# `shtl init` passes them straight through to the script.
readonly SHTL_COMMANDS="add update remove rm list ls clean persist path doctor setup unsetup init help version"


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
	shtl_log "ERROR" "${ROUTES_FILE} is not a shtl routes file. Its first line must be: ${ROUTES_HEADER}. To find the problem, run: shtl doctor"
	exit 1
}

# Replaces the routes file with the output of the given command. The output
# goes to a unique temp file next to the real file, then moves over it, so:
# a symlinked routes file (e.g. from a dotfiles repo) stays a symlink, two
# shtl commands never share a temp file, and a failed write changes nothing.
# mktemp makes the file 0600, so cp -p copies the real file's mode onto it
# first. >| then writes even when noclobber is on.
shtl_write_routes() {
	local target="$ROUTES_FILE" tmp
	if [[ -L $target ]]; then
		target="$(realpath "$target")" || return 1
	fi
	tmp="$(mktemp "${target}.XXXXXX")" || return 1
	if cp -p "$target" "$tmp" && "$@" >| "$tmp" && mv -f "$tmp" "$target"; then
		return 0
	fi
	rm -f "$tmp"
	return 1
}

# The routes file keeps the user's order, comments and blank lines: each
# command changes only its own line. Output is sorted when routes are read.

# The routes file plus a new entry at the end. awk '1' adds a missing final
# newline, so the entry can't join the last line.
shtl_print_routes_with_entry() {
	awk '1' "$ROUTES_FILE"
	echo "$1"
}

# The routes file with the named route's line replaced, in place
shtl_print_routes_replacing() {
	SHTL_ROUTE_NAME="$1" SHTL_NEW_ENTRY="$2" awk 'index($0, ENVIRON["SHTL_ROUTE_NAME"] "[") == 1 { print ENVIRON["SHTL_NEW_ENTRY"]; next } 1' "$ROUTES_FILE"
}

# Prints every route entry sorted by name, skipping the header, comments
# and blank lines
shtl_get_entries() {
	awk '!/^#/ && /[^[:space:]]/' "$ROUTES_FILE" | sort --ignore-case -t '[' -k1,1
}

shtl_usage() {
	echo ""
	echo "$(basename "$0") - Help"
	echo ""
	echo "  Usage: shtl ROUTE_NAME [SUBDIR]"
	echo "         shtl COMMAND [ARGS]"
	echo ""
	echo "    ROUTE_NAME [SUBDIR]             Jump to a route, or a folder under it (needs the shell function, see setup)"
	echo "    add NAME [PATH] [-p|--persist]  Add a route. PATH must be absolute and defaults to the current directory"
	echo "                                    --persist allows a directory that doesn't exist yet, and clean skips the route"
	echo "    update NAME [PATH]              Point a route at a new absolute path. PATH defaults to the current directory"
	echo "    remove | rm NAME                Remove a route"
	echo "    list | ls                       List routes. * marks the route you are in"
	echo "    clean                           Interactively remove routes whose directories no longer exist"
	echo "    persist NAME                    Toggle whether clean skips a route"
	echo "    path NAME [SUBDIR]              Print a route's path (e.g. cp file \"\$(shtl path work)\")"
	echo "    doctor                          Check the routes file for problems"
	echo "    setup                           Add the shell function to your shell's rc file (asks first)"
	echo "    unsetup                         Remove the shell function from your rc files (asks first)"
	echo "    init                            Print the shell function. setup adds it to your rc file for you"
	echo "    help                            Display this information"
	echo "    version                         Print the shtl version"
	echo ""
}

# Names are matched as literal strings, not regexes, so "a.b" can't match "axb"
shtl_get_route_entry() {
	SHTL_ROUTE_NAME="$1" awk 'index($0, ENVIRON["SHTL_ROUTE_NAME"] "[") == 1' "$ROUTES_FILE"
}

shtl_print_routes_without() {
	SHTL_ROUTE_NAME="$1" awk 'index($0, ENVIRON["SHTL_ROUTE_NAME"] "[") != 1' "$ROUTES_FILE"
}

shtl_remove_route_entry() {
	shtl_write_routes shtl_print_routes_without "$1"
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

# A stored path that starts with "~" is under the home directory, so one
# routes file works on machines with different homes (/Users/me, /home/me).
# The "~" in these functions is the literal stored text, never expanded.
# shellcheck disable=SC2088
shtl_expand_path() {
	local home="${HOME%/}"
	case $1 in
		"~") echo "${home:-/}" ;;
		"~/"*) echo "${home}/${1#"~/"}" ;;
		*) echo "$1" ;;
	esac
}

# The reverse, for storing: a path in the home directory becomes ~ or ~/...
# shellcheck disable=SC2088
shtl_contract_path() {
	local home="${HOME%/}"
	if [[ -n $home && $1 == "$home" ]]; then
		echo "~"
	elif [[ -n $home && $1 == "$home"/* ]]; then
		echo "~/${1#"$home"/}"
	else
		echo "$1"
	fi
}

shtl_get_route() {
	local route
	route=$(shtl_get_route_entry "$1")
	shtl_expand_path "$(shtl_get_entry_path "$route")"
}

shtl_get_route_names(){
	local entry
	while IFS='' read -r entry; do
		shtl_get_entry_name "$entry"
	done < <(shtl_get_entries)
}

# Logs the routes whose names start with $1, ignoring case, for an unknown
# name. Never picks one: the user types it (or tab-completes it). Returns 1
# when nothing matches.
shtl_suggest_routes() {
	local suggestions
	suggestions="$(shtl_get_route_names | SHTL_PREFIX="$1" awk 'index(tolower($0), tolower(ENVIRON["SHTL_PREFIX"])) == 1 { out = out (n++ ? ", " : "") $0 } END { if (n) print out }')"
	[[ -n $suggestions ]] || return 1
	shtl_log "INFO" "Did you mean: ${suggestions}"
}

# Warns about other routes that point to the same directory as route $1.
# $2 is the real path; stored ~/ paths are expanded before comparing.
shtl_warn_shared_dir() {
	local name="$1" path="$2" entry other
	while IFS='' read -r entry; do
		other="$(shtl_get_entry_name "$entry")"
		[[ $other == "$name" ]] && continue
		if [[ $(shtl_expand_path "$(shtl_get_entry_path "$entry")") == "$path" ]]; then
			shtl_log "WARN" "Route \"${other}\" also points to ${path}"
		fi
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

# True when directory $2 is $1 or inside it
shtl_path_contains() {
	[[ $2 == "$1" || $1 == / || $2 == "$1"/* ]]
}

# Prints NAME  PATH columns, marking persistent routes. When the current
# directory is in a route, a "* " column marks the closest one (the longest
# path that contains it; several routes if they share that directory).
shtl_list_routes() {
	local entry name path i cwd pointer width=0 best=-1
	local names=() paths=() marks=() expanded=()
	if ! shtl_has_routes; then
		shtl_log "INFO" "No routes yet. Add one with: shtl add NAME [PATH]"
		return 0
	fi
	cwd="$(shtl_get_current_path 2> /dev/null)"
	while IFS='' read -r entry; do
		name="$(shtl_get_entry_name "$entry")"
		path="$(shtl_get_entry_path "$entry")"
		names+=("$name")
		paths+=("$path")
		expanded+=("$(shtl_expand_path "$path")")
		if shtl_entry_is_persistent "$entry"; then
			marks+=("  (persist)")
		else
			marks+=("")
		fi
		(( ${#name} > width )) && width=${#name}
	done < <(shtl_get_entries)
	if [[ -n $cwd ]]; then
		for i in "${!expanded[@]}"; do
			if shtl_path_contains "${expanded[i]}" "$cwd" && (( ${#expanded[i]} > best )); then
				best=${#expanded[i]}
			fi
		done
	fi
	for i in "${!names[@]}"; do
		if (( best < 0 )); then
			pointer=""
		elif (( ${#expanded[i]} == best )) && shtl_path_contains "${expanded[i]}" "$cwd"; then
			pointer="* "
		else
			pointer="  "
		fi
		printf '%s%-*s  %s%s\n' "$pointer" "$width" "${names[i]}" "${paths[i]}" "${marks[i]}"
	done
	# Routes added before a command of the same name existed can't be jumped to
	for name in "${names[@]}"; do
		if shtl_is_command "$name"; then
			shtl_log "WARN" "Route \"${name}\" has the same name as a shtl command, so shtl ${name} runs the command. Use: cd \"\$(shtl path ${name})\", or remove it and add it under a new name"
		fi
	done
}

# Prints the path a route stores: PATH, or the current directory, normalized.
# pwd fails, printing nothing, when the current directory was deleted.
shtl_resolve_path() {
	local path="$1"
	if [[ -z $path ]] && ! path="$(shtl_get_current_path 2> /dev/null)"; then
		shtl_log "ERROR" "The current directory does not exist anymore. Give a PATH, or cd to an existing directory"
		return 1
	fi
	shtl_normalize_path "$path"
}

# A route must point to a directory. Only a persistent route can point to one
# that doesn't exist yet. Checks the resolved path, the one the route stores.
# Usage: shtl_check_route_dir PATH PERSISTENT(yes|"") HINT
shtl_check_route_dir() {
	local path="$1" persistent="$2" hint="$3"
	if [[ -e $path && ! -d $path ]]; then
		shtl_log "ERROR" "\"${path}\" is not a directory"
		return 1
	fi
	if [[ -z $persistent && ! -d $path ]]; then
		shtl_log "ERROR" "\"${path}\" does not exist. Only a persistent route can point to a missing directory. ${hint}"
		return 1
	fi
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
	local route providedPath
	providedPath="$(shtl_expand_path "$2")"
	shtl_validate_path "$providedPath" || return 1
	route="$(shtl_resolve_path "$providedPath")" || return 1
	shtl_check_route_dir "$route" "$3" "To add a route for a directory that will exist later, use --persist" || return 1
	shtl_write_routes shtl_print_routes_with_entry "$(shtl_format_entry "$1" "$3" "$(shtl_contract_path "$route")")" || return 1
	shtl_warn_shared_dir "$1" "$route"
}

shtl_delete_route() {
	local routeName="$1"
	if shtl_route_name_exists "$routeName"; then
		shtl_remove_route_entry "$routeName"
	else
		shtl_log "ERROR" "Could not remove route \"${routeName}\". The route does not exist"
		shtl_suggest_routes "$routeName"
		return 1
	fi
}

# Points an existing route at a new path, keeping its flags
shtl_update_route() {
	local routeName="$1"
	local providedPath
	providedPath="$(shtl_expand_path "$2")"
	local entry route persistent=""
	if ! shtl_route_name_exists "$routeName"; then
		shtl_log "ERROR" "Could not update route \"${routeName}\". The route does not exist"
		shtl_suggest_routes "$routeName"
		return 1
	fi
	shtl_validate_path "$providedPath" || return 1
	entry="$(shtl_get_route_entry "$routeName")"
	route="$(shtl_resolve_path "$providedPath")" || return 1
	shtl_entry_is_persistent "$entry" && persistent="yes"
	shtl_check_route_dir "$route" "$persistent" "To make this route persistent, run: shtl persist ${routeName}. Then run this update again" || return 1
	shtl_write_routes shtl_print_routes_replacing "$routeName" "$(shtl_format_entry "$routeName" "$(shtl_get_entry_flags "$entry")" "$(shtl_contract_path "$route")")" || return 1
	shtl_warn_shared_dir "$routeName" "$route"
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
		[[ -d $(shtl_expand_path "$path") ]] && continue
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
		shtl_suggest_routes "$routeName"
		return 1
	fi
	entry="$(shtl_get_route_entry "$routeName")"
	flags="$(shtl_get_entry_flags "$entry")"
	if shtl_entry_is_persistent "$entry"; then
		shtl_check_route_dir "$(shtl_expand_path "$(shtl_get_entry_path "$entry")")" "" "Point it at an existing directory with: shtl update ${routeName} PATH, or remove it" || return 1
		# Drop "persist" from the comma-separated flags, keeping any others
		flags=",${flags},"
		flags="${flags//,persist,/,}"
		flags="${flags#,}"
		flags="${flags%,}"
	else
		flags="${flags:+${flags},}persist"
	fi
	newEntry="$(shtl_format_entry "$routeName" "$flags" "$(shtl_get_entry_path "$entry")")"
	shtl_write_routes shtl_print_routes_replacing "$routeName" "$newEntry" || return 1
	if shtl_entry_is_persistent "$newEntry"; then
		shtl_log "INFO" "Route \"${routeName}\" is now persistent. Clean will skip it"
	else
		shtl_log "INFO" "Route \"${routeName}\" is no longer persistent"
	fi
}

# Prints only the route's path, for the shell function and for use in
# scripts. An optional second argument is a folder under the route.
shtl_print_path(){
	local routeName="$1" subdir="$2"
	local path
	if ! shtl_route_name_exists "$routeName"; then
		shtl_log "ERROR" "Route \"${routeName}\" does not exist"
		shtl_suggest_routes "$routeName"
		return 1
	fi
	path="$(shtl_get_route "$routeName")"
	if [[ ! -d $path ]]; then
		shtl_log "ERROR" "Route \"${routeName}\" points to ${path}, which doesn't exist"
		return 1
	fi
	if [[ -n $subdir ]]; then
		if [[ $subdir == /* ]]; then
			shtl_log "ERROR" "\"${subdir}\" must be relative to the route. Leave out the leading \"/\""
			return 1
		fi
		path="$(shtl_normalize_path "${path}/${subdir}")"
		if [[ ! -d $path ]]; then
			shtl_log "ERROR" "\"${path}\" does not exist"
			return 1
		fi
	fi
	echo "$path"
}

# A script can't change its parent shell's directory. Without the shell
# function from `shtl init`, print the path and explain how to set it up.
shtl_route(){
	shtl_print_path "$1" "$2" || return 1
	shtl_log "WARN" "shtl can't change directory without its shell function. To set it up, run: shtl setup"
}

# Reports routes file problems that can break shtl, with line numbers.
# It only reports: the user fixes the file in a text editor.
shtl_doctor(){
	local line trimmed stripped name flags path flag i
	local lineNumber=0
	local problems=() seenNames=() seenLines=() flagList=()
	local entryPattern='^([^]:[]*)\[([^]]*)\]:(.*)$'
	if [[ ! -f $ROUTES_FILE ]]; then
		echo "There is no routes file yet. Nothing to check"
		return 0
	fi
	while IFS='' read -r line || [[ -n $line ]]; do
		lineNumber=$((lineNumber + 1))
		if [[ $line == *$'\r'* ]]; then
			problems+=("Line ${lineNumber}: has a Windows line ending (\\r). Save the file with Unix line endings")
		fi
		trimmed="${line//$'\r'/}"
		stripped="${trimmed%"${trimmed##*[![:space:]]}"}"
		# shtl ignores blank lines, but not on line 1, which must be the header
		if [[ -z $stripped && $lineNumber -gt 1 ]]; then
			continue
		fi
		if [[ $trimmed != "$stripped" ]]; then
			problems+=("Line ${lineNumber}: ends with spaces or tabs. Remove them")
		fi
		if [[ $lineNumber -eq 1 ]]; then
			if [[ $stripped != "$ROUTES_HEADER" ]]; then
				problems+=("Line 1: must be: ${ROUTES_HEADER}")
			fi
			continue
		fi
		[[ $stripped == '#'* ]] && continue
		if [[ ! $stripped =~ $entryPattern ]]; then
			problems+=("Line ${lineNumber}: is not a route in the format NAME[FLAGS]:PATH")
			continue
		fi
		name="${BASH_REMATCH[1]}"
		flags="${BASH_REMATCH[2]}"
		path="${BASH_REMATCH[3]}"
		if ! shtl_is_valid_name_format "$name" || [[ $name == -* ]]; then
			problems+=("Line ${lineNumber}: route name \"${name}\" is not valid. Names can't be empty, contain \":\", \"[\" or \"]\", or start with \"-\"")
		elif shtl_is_command "$name"; then
			problems+=("Line ${lineNumber}: route name \"${name}\" is a shtl command, so shtl can't go to this route. Rename it")
		fi
		for i in "${!seenNames[@]}"; do
			if [[ ${seenNames[$i]} == "$name" ]]; then
				problems+=("Line ${lineNumber}: route name \"${name}\" is also on line ${seenLines[$i]}. Remove or rename one of them")
				break
			fi
		done
		seenNames+=("$name")
		seenLines+=("$lineNumber")
		flagList=()
		[[ -n $flags ]] && IFS=',' read -r -a flagList <<< "$flags"
		for flag in "${flagList[@]}"; do
			if [[ $flag != persist ]]; then
				problems+=("Line ${lineNumber}: \"${flag}\" is not a flag. The only flag is persist")
			fi
		done
		# shellcheck disable=SC2088 # a literal stored "~", not to be expanded
		if [[ $path != /* && $path != "~" && $path != "~/"* ]]; then
			problems+=("Line ${lineNumber}: path \"${path}\" is not absolute. It must start with \"/\" or \"~/\"")
		fi
	done < "$ROUTES_FILE"
	if [[ ${#problems[@]} -eq 0 ]]; then
		echo "No problems found in ${ROUTES_FILE}"
		return 0
	fi
	echo "Problems found in ${ROUTES_FILE}:"
	printf '  %s\n' "${problems[@]}"
	return 1
}

# The lines `shtl setup` adds to an rc file. The marker lets unsetup find them.
readonly SHTL_RC_MARKER="# shtl: https://github.com/bitmvr-industries/shtl"
# shellcheck disable=SC2016 # written to the rc file literally, expanded there
readonly SHTL_RC_LINE='if command -v shtl >/dev/null; then eval "$(shtl init)"; fi'

# The login file bash reads: the first of these that exists. If none exists,
# ~/.bash_profile. Making ~/.bash_profile when ~/.profile exists would stop
# bash from reading ~/.profile.
shtl_bash_login_file() {
	local file
	for file in .bash_profile .bash_login .profile; do
		if [[ -e $HOME/$file ]]; then
			echo "$HOME/$file"
			return 0
		fi
	done
	echo "$HOME/.bash_profile"
}

# True when file $1 sources ~/.bashrc on a line that isn't a comment, e.g.
# `[ -f ~/.bashrc ] && . ~/.bashrc` or `source "$HOME/.bashrc"`
shtl_sources_bashrc() {
	# shellcheck disable=SC2016 # $HOME is matched literally, not expanded
	grep -Eqs '^[^#]*(^|[[:space:];&|{(])(source|\.)[[:space:]]+["'\'']?(~|\$HOME|\$\{HOME\})["'\'']?/\.bashrc(["'\''[:space:];&|)]|$)' "$1"
}

# Prints the rc files that the user's login shell reads at startup and that
# setup can use, one per line. The last one is the file setup edits. Prints
# nothing for shells other than bash and zsh.
shtl_rc_files() {
	local login
	case $SHELL in
		*/zsh)
			echo "${ZDOTDIR:-$HOME}/.zshrc"
			;;
		*/bash)
			# macOS terminals open login shells, which don't read ~/.bashrc
			# unless the login file sources it. Linux terminals read ~/.bashrc.
			if [[ $(uname) == Darwin ]]; then
				login="$(shtl_bash_login_file)"
				echo "$login"
				if shtl_sources_bashrc "$login"; then
					echo "$HOME/.bashrc"
				fi
			else
				echo "$HOME/.bashrc"
			fi
			;;
	esac
}

# Every rc file unsetup checks for the lines, wherever setup put them before
shtl_all_rc_files() {
	case $SHELL in
		*/zsh) echo "${ZDOTDIR:-$HOME}/.zshrc" ;;
		*/bash) printf '%s\n' "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile" "$HOME/.bashrc" ;;
	esac
}

# Asks a yes/no question. No without a terminal, so scripts never edit files.
shtl_confirm() {
	local reply
	[[ -t 0 ]] || return 1
	read -r -p "$1 [y/N] " reply
	[[ $reply == [yY] || $reply == [yY][eE][sS] ]]
}

shtl_print_rc_lines() {
	echo ""
	echo "    $SHTL_RC_MARKER"
	echo "    $SHTL_RC_LINE"
	echo ""
	if [[ -L $1 ]]; then
		echo "Note: $(shtl_contract_path "$1") is a symlink to $(readlink "$1"). The change will be made in that file."
	fi
}

# Offers to add the shell function to the rc file of the user's shell
shtl_setup() {
	local files=() file rc shown
	while IFS='' read -r file; do
		files+=("$file")
	done < <(shtl_rc_files)

	if [[ ${#files[@]} -eq 0 ]]; then
		echo "shtl's shell function supports bash and zsh. Without it, use: cd \"\$(shtl path ROUTE_NAME)\""
		return 0
	fi

	for file in "${files[@]}"; do
		if grep -qs 'shtl init' "$file"; then
			echo "Shell integration already set up in $(shtl_contract_path "$file")"
			return 0
		fi
	done

	rc="${files[${#files[@]}-1]}"
	shown="$(shtl_contract_path "$rc")"
	echo "shtl needs these lines in $shown to change directories and tab-complete routes."
	if [[ ${#files[@]} -gt 1 ]]; then
		echo "$(shtl_contract_path "${files[0]}") sources ~/.bashrc, so the lines go in ~/.bashrc."
	fi
	shtl_print_rc_lines "$rc"

	if shtl_confirm "Append them to the end of $shown?"; then
		# Separate from existing content with a blank line, unless the file is empty
		if [[ -s $rc ]]; then
			echo "" >> "$rc"
		fi
		printf '%s\n%s\n' "$SHTL_RC_MARKER" "$SHTL_RC_LINE" >> "$rc"
		echo "Added. Open a new terminal, or run: source $shown"
	elif [[ $SHELL == */zsh ]]; then
		echo "Skipped. To set it up yourself, add those lines to the end of $shown"
		echo "(after compinit, so tab completion works), then open a new terminal."
	else
		echo "Skipped. To set it up yourself, add those lines to the end of $shown, then open a new terminal."
	fi
}

# Removes the marker, the line after it, and the blank line setup added
# before them. Writes back in place, so symlinks and permissions are kept.
shtl_remove_rc_lines() {
	local tmp
	tmp="$(mktemp)" || return 1
	awk -v marker="$SHTL_RC_MARKER" -v init="$SHTL_RC_LINE" '
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
	' "$1" > "$tmp" && cat "$tmp" >| "$1"
	rm -f "$tmp"
}

# Offers to remove the lines setup added, from each rc file that has them
shtl_unsetup() {
	local files=() file shown found=""
	# Read the list first: the prompts below need stdin
	while IFS='' read -r file; do
		files+=("$file")
	done < <(shtl_all_rc_files)

	for file in "${files[@]}"; do
		[[ -f $file ]] || continue
		shown="$(shtl_contract_path "$file")"
		if grep -qxF "$SHTL_RC_MARKER" "$file"; then
			found=1
			echo "$shown has shtl's shell integration lines."
			shtl_print_rc_lines "$file"
			if shtl_confirm "Remove them from $shown?"; then
				shtl_remove_rc_lines "$file" && echo "Removed."
			else
				echo "Kept. The line is guarded, so it does nothing while shtl isn't installed."
			fi
		elif grep -qs 'shtl init' "$file"; then
			found=1
			echo "$shown runs 'shtl init'. setup didn't add that line, so remove it yourself."
		fi
	done

	if [[ -z $found ]]; then
		echo "No shtl lines in your rc files"
	fi
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
			dest="$(command shtl path "$@")" && cd -- "$dest"
			;;
	esac
}

if [ -n "$ZSH_VERSION" ]; then
	_shtl() {
		local -a routes subcommands
		local base
		routes=(${(f)"$(command shtl list --names)"})
		subcommands=(__SHTL_COMMANDS__)
		if (( CURRENT == 2 )); then
			compadd -a subcommands
			compadd -a routes
		elif (( CURRENT == 3 )); then
			case "${words[2]}" in
				remove|rm|update|persist|path) compadd -a routes ;;
				*)
					# A route: complete folders under its path
					if (( ! ${subcommands[(Ie)${words[2]}]} )); then
						base="$(command shtl path "${words[2]}" 2>/dev/null)" && _files -/ -W "$base"
					fi
					;;
			esac
		elif (( CURRENT == 4 )) && [[ "${words[2]}" == add || "${words[2]}" == update ]]; then
			_files -/
		elif (( CURRENT == 4 )) && [[ "${words[2]}" == path ]]; then
			base="$(command shtl path "${words[3]}" 2>/dev/null)" && _files -/ -W "$base"
		fi
	}
	if (( $+functions[compdef] )); then
		compdef _shtl shtl
	fi
elif [ -n "$BASH_VERSION" ]; then
	# Folders under route $1 that start with $2, each ending in "/" so Tab can
	# go a level deeper. bash 3.2 has no compopt, so it adds a space after each.
	_shtl_subdirs() {
		local base dir IFS=$'\n'
		base="$(command shtl path "$1" 2>/dev/null)" || return
		COMPREPLY=()
		for dir in $(cd -- "$base" && compgen -d -- "$2"); do
			COMPREPLY+=("$dir/")
		done
		compopt -o nospace 2>/dev/null
	}
	_shtl() {
		local cur="${COMP_WORDS[COMP_CWORD]}"
		local words=""
		if [ "$COMP_CWORD" -eq 1 ]; then
			words="__SHTL_COMMANDS__ $(command shtl list --names)"
		elif [ "$COMP_CWORD" -eq 2 ]; then
			case "${COMP_WORDS[1]}" in
				remove|rm|update|persist|path) words="$(command shtl list --names)" ;;
				*)
					case " __SHTL_COMMANDS__ " in
						*" ${COMP_WORDS[1]} "*) ;;
						*) _shtl_subdirs "${COMP_WORDS[1]}" "$cur"; return ;;
					esac
					;;
			esac
		elif [ "$COMP_CWORD" -eq 3 ] && [ "${COMP_WORDS[1]}" = path ]; then
			_shtl_subdirs "${COMP_WORDS[2]}" "$cur"
			return
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
