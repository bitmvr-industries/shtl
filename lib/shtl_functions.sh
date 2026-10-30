#!/usr/bin/env bash

# Route List (XDG Base Directory spec)
readonly CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/shtl"
readonly ROUTES_FILE="$CONFIG_DIR/routes"
readonly USAGE="$(dirname "$0")"


shtl_log() {
  local log_level="${1}"
  local msg="${2}"
  local log_entry=$(echo -e "\r\n$(basename "${0}") $(printf "%-7s" ["${log_level}"]) ${msg}\r\n\r\n")
	
	echo -e "$log_entry"
}

shtl_validate_arguments(){
	if [[ $# -eq 0 ]]; then
		shtl_log "ERROR" "Please provide a route name"
		exit
	fi
}

shtl_init(){
	mkdir -p "$CONFIG_DIR"
	if [[ ! -f $ROUTES_FILE ]]; then
		touch "$ROUTES_FILE"
	fi
}

shtl_refresh_routes() {
  grep -v "^$" "$ROUTES_FILE" | sort --ignore-case  > "$ROUTES_FILE.tmp" && mv "$ROUTES_FILE.tmp" "$ROUTES_FILE" && echo "" >> "$ROUTES_FILE"
}

shtl_usage() {
	echo ""
	echo "$(basename "$0") - Help"
	echo ""
	echo "    -l | --list    Display available routes"
	echo "    -h | --help    Display this information"
	echo "    -a | --add     ROUTE_NAME [ROUTE] [-p|--persist] Add a route. Provide only the name unless you're not current in the desired route path"
	echo "                   --persist keeps the route even if its directory doesn't exist (clean will skip it)"
	echo "    -c | --clean   Interactively remove routes whose directories no longer exist"
	echo "    -p | --persist ROUTE_NAME Toggle whether clean skips a route"
	echo "    -d | --delete  ROUTE_NAME Delete a route via its route name"
	echo "    -m | --modify  ROUTE_NAME ROUTE Modify a route via its route name"
	echo "    -v | --version Prints current shtl version"
	echo ""
}

shtl_get_route_entry() {
	routeName="$1"
	grep "^${routeName}:" "$ROUTES_FILE"
}

# Strips the route name and any :persist marker from an entry
shtl_get_entry_path() {
	local entry="$1"
	local route="${entry#*:}"
	echo "${route%:persist}"
}

shtl_entry_is_persistent() {
	[[ "$1" == *:persist ]]
}

shtl_get_route() {
	local route
	route=$(shtl_get_route_entry "$1")
	shtl_get_entry_path "$route"
}

shtl_get_route_names(){
	for route in $(shtl_get_route_entry); do
		echo "${route%:*}"
	done
}

shtl_get_current_path() {
	pwd
}

shtl_list_routes() {
	while IFS='' read -r route || [[ -n "$route" ]]; do
    	echo "$route"
	done < "$ROUTES_FILE" 
}

shtl_generate_route() {	
	local currentDir
	currentDir="$(shtl_get_current_path)"
	local routeName="$1"
	local providedPath="$2"
	local persist="$3"
	local route="${providedPath:-$currentDir}"
	if [[ -n $persist ]]; then
		echo "${routeName}:${route}:persist"
	else
		echo "${routeName}:${route}"
	fi
}

shtl_route_name_exists(){
	local routeName="$1"
	grep -q "^${routeName}:" "$ROUTES_FILE"
}

shtl_add_route(){
	if shtl_route_name_exists "$1"; then
		shtl_log "ERROR" "It appears this route already exists in your routes"
		return 1
		exit
	fi	
	shtl_generate_route "$@" >> "$ROUTES_FILE" && shtl_refresh_routes
}

shtl_delete_route() {
	local routeName="$1"
	if shtl_route_name_exists $routeName; then
		grep -v "^${routeName}:" "$ROUTES_FILE"  > "$ROUTES_FILE.tmp" && mv "$ROUTES_FILE.tmp" "$ROUTES_FILE"
	else
		shtl_log "ERROR" "Could not delete route \"${routeName}\". The route does not exist"
	fi
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

	while IFS='' read -r entry || [[ -n "$entry" ]]; do
		[[ -z $entry ]] && continue
		shtl_entry_is_persistent "$entry" && continue
		path="$(shtl_get_entry_path "$entry")"
		[[ -d $path ]] && continue
		names+=("${entry%%:*}")
		paths+=("$path")
		selected+=(1)
	done < "$ROUTES_FILE"

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
	local entry newEntry
	if ! shtl_route_name_exists "$routeName"; then
		shtl_log "ERROR" "Could not persist route \"${routeName}\". The route does not exist"
		return 1
	fi
	entry="$(shtl_get_route_entry "$routeName")"
	if shtl_entry_is_persistent "$entry"; then
		newEntry="${entry%:persist}"
	else
		newEntry="${entry}:persist"
	fi
	grep -v "^${routeName}:" "$ROUTES_FILE" > "$ROUTES_FILE.tmp" && mv "$ROUTES_FILE.tmp" "$ROUTES_FILE"
	echo "$newEntry" >> "$ROUTES_FILE" && shtl_refresh_routes
	if shtl_entry_is_persistent "$newEntry"; then
		shtl_log "INFO" "Route \"${routeName}\" is now persistent. Clean will skip it"
	else
		shtl_log "INFO" "Route \"${routeName}\" is no longer persistent"
	fi
}

shtl_modify_route_name() {
	shtl_log "WARN" "This feature doesn't currently exist"
}

shtl_route(){
	cd "$(shtl_get_route "$1")" || exit
	shtl_log "INFO" "Current directory is $(pwd)"
}

shtl_version(){
	cat "$(dirname $(basename "$0"))/VERSION"
}
