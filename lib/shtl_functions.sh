#!/usr/bin/env bash

# Route List
readonly SWITCHBOARD="$HOME/.shuttle_switchboard"

if [[ ! -f $SWITCHBOARD ]]; then
	touch $SWITCHBOARD
fi

function shuttle::usage() {
	echo ""
	echo "$(basename "$0") - Help"
	echo ""
	echo "    -l | --list  Display available routes"
	echo "    -h | --help  Display this information"
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
	grep -q "^${routeName}:" $SWITCHBOARD
}

function shuttle::addRoute(){
	shuttle::generateRoute "$@" >> $SWITCHBOARD
}

function shuttle::deleteRoute() {
	local routeName="$1"
	grep -v ^"${routeName}:" $SWITCHBOARD  > "$SWITCHBOARD.tmp" && mv "$SWITCHBOARD.tmp" $SWITCHBOARD
}

function shuttle::updateRoute() {
	echo "Hello from ${FUNCNAME[0]}"	
}

function shuttle::route(){
	cd $(shuttle::getRoute "$1")
}
