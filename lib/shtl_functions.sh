#!/usr/bin/env bash

# Route List
readonly SWITCHBOARD="$HOME/.shuttle_switchboard"
readonly USAGE="$(dirname "$0")"


shuttle::log() {
  local log_level="${1}"
  local msg="${2}"
  local log_entry=$(echo -e "\r\n$(basename "${0}") $(printf "%-7s" ["${log_level}"]) ${msg}\r\n\r\n")
	
	echo -e "$log_entry"
}

shuttle::validateArguments(){
	if [[ $# -eq 0 ]]; then
		shuttle::log "ERROR" "Please provide a route name"
		exit
	fi
}

shuttle::init(){
	if [[ ! -f $SWITCHBOARD ]]; then
		touch "$SWITCHBOARD"
	fi
}

shuttle::switchboardRefresh() {
  grep -v "^$" "$SWITCHBOARD" | sort --ignore-case  > "$SWITCHBOARD.tmp" && mv "$SWITCHBOARD.tmp" "$SWITCHBOARD" && echo "" >> "$SWITCHBOARD"
}

shuttle::usage() {
	echo ""
	echo "$(basename "$0") - Help"
	echo ""
	echo "    -l | --list    Display available routes"
	echo "    -h | --help    Display this information"
	echo "    -a | --add     RouteName (Route) Add a route. Provide only the name unless you're not current in the desired route path"
	echo "    -d | --delete  RouteName Delete a route via its route name"
	echo "    -m | --modify  RouteName Delete a route via its route name"
	echo "    -v | --version Prints current shtl version"
	echo ""
}

shuttle::getRouteEntry() {
	routeName="$1"
	grep "$routeName" "$SWITCHBOARD"
}

shuttle::getRoute() {
	local route
	route=$(shuttle::getRouteEntry "$1")
	echo "${route#*\:}"
}

shuttle::getRouteNames(){
	for route in $(shuttle::getRouteEntry); do
		echo "${route%:*}"
	done
}

shuttle::getCurrentPath() {
	pwd
}

shuttle::listRoutes() {
	while IFS='' read -r route || [[ -n "$route" ]]; do
    	echo "$route"
	done < "$SWITCHBOARD" 
}

shuttle::generateRoute() {	
	local currentDir
	currentDir="$(shuttle::getCurrentPath)"
	local routeName="$1"
	local providedPath="$2"
	local route="${providedPath:-$currentDir}"
	echo "${routeName}:${route}"
}

shuttle::routeNameExists(){
	local routeName="$1"
	grep -q "^${routeName}:" "$SWITCHBOARD"
}

shuttle::addRoute(){
	if shuttle::routeNameExists "$1"; then
		shuttle::log "ERROR" "It appears this route already exists in the switchboard"
		return 1
		exit
	fi	
	shuttle::generateRoute "$@" >> "$SWITCHBOARD" && shuttle::switchboardRefresh
}

shuttle::deleteRoute() {
	local routeName="$1"
	if shuttle::routeNameExists $routeName; then
		grep -v "^${routeName}:" "$SWITCHBOARD"  > "$SWITCHBOARD.tmp" && mv "$SWITCHBOARD.tmp" "$SWITCHBOARD"
	else
		shuttle::log "ERROR" "Could not delete route \"${routeName}\". The route does not exist"
	fi
}

shuttle::modifyRouteName() {
	shuttle::log "WARN" "This feature doesn't currently exist"
}

shuttle::route(){
	cd "$(shuttle::getRoute "$1")" || exit
	shuttle::log "INFO" "Current directory is $(pwd)"
}

shuttle::version(){
	cat "$(dirname $(basename "$0"))/VERSION"
}
