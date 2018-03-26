#!/usr/bin/env bash

# Route List
readonly SWITCHBOARD="$HOME/.shuttle_switchboard"
readonly USAGE="$(dirname "$0")"


function shuttle::log() {
  local log_level="${1}"
  local msg="${2}"
  local log_entry=$(echo -e "\r\n$(basename "${0}") $(printf "%-7s" ["${log_level}"]) ${msg}\r\n\r\n")
	
	echo -e "$log_entry"
}

function shuttle::validateArguments(){
	if [[ $# -eq 0 ]]; then
		shuttle::log "ERROR" "Please provide a route name"
		exit
	fi
}

function shuttle::init(){
	if [[ ! -f $SWITCHBOARD ]]; then
		touch "$SWITCHBOARD"
	fi
}

function shuttle::switchboardRefresh() {
  grep -v "^$" "$SWITCHBOARD" | sort --ignore-case  > "$SWITCHBOARD.tmp" && mv "$SWITCHBOARD.tmp" "$SWITCHBOARD" && echo "" >> "$SWITCHBOARD"
}

function shuttle::usage() {
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

function shuttle::getRouteEntry() {
	routeName="$1"
	grep "$routeName" "$SWITCHBOARD"
}

function shuttle::getRoute() {
	local route
	route=$(shuttle::getRouteEntry "$1")
	echo "${route#*\:}"
}

function shuttle::getRouteNames(){
	for route in $(shuttle::getRouteEntry); do
		echo "${route%:*}"
	done
}

function shuttle::getCurrentPath() {
	pwd
}

function shuttle::listRoutes() {
	while IFS='' read -r route || [[ -n "$route" ]]; do
    	echo "$route"
	done < "$SWITCHBOARD" 
}

function shuttle::generateRoute() {	
	local currentDir
	currentDir="$(shuttle::getCurrentPath)"
	local routeName="$1"
	local providedPath="$2"
	local route="${providedPath:-$currentDir}"
	echo "${routeName}:${route}"
}

function shuttle::routeNameExists(){
	local routeName="$1"
	grep -q "^${routeName}:" "$SWITCHBOARD"
}

function shuttle::addRoute(){
	if shuttle::routeNameExists "$1"; then
		shuttle::log "ERROR" "It appears this route already exists in the switchboard"
		return 1
		exit
	fi	
	shuttle::generateRoute "$@" >> "$SWITCHBOARD" && shuttle::switchboardRefresh
}

function shuttle::deleteRoute() {
	local routeName="$1"
	if shuttle::routeNameExists $routeName; then
		grep -v "^${routeName}:" "$SWITCHBOARD"  > "$SWITCHBOARD.tmp" && mv "$SWITCHBOARD.tmp" "$SWITCHBOARD"
	else
		shuttle::log "ERROR" "Could not delete route \"${routeName}\". The route does not exist"
	fi
}

function shuttle::modifyRouteName() {
	shuttle::log "WARN" "This feature doesn't currently exist"
}

function shuttle::route(){
	cd "$(shuttle::getRoute "$1")" || exit
}

function shuttle::version(){
	cat "$(dirname $(basename "$0"))/VERSION"
}
