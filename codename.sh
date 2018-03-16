#!/usr/bin/env bash


# Route Argument
readonly routeName="${1}"

# Route List
readonly SWITCHBOARD='switchboard'

function shuttle::usage() {
	echo ""
	echo "$(basename "$0") - Help"
	echo ""
	echo "    -l | --list  Display available routes"
	echo "    -h | --help  Display this information"
	echo ""
}

if [ "$#" -eq 0 ]; then
	echo "No arguments were passed"
	echo "$(usage)"
fi

function shuttle::getRouteEntry() {
	grep "$routeName" "$SWITCHBOARD"
}

function shuttle::getRoute() {
	local route=$(shuttle::getRouteEntry)
	echo "${route#*\:}"
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
	local currentDir="$(shuttle::getCurrentPath)"
	local providedPath="$2"
	local route="${providedPath:-$currentDir}"
	echo "${routeName}:${route}"
}

function shuttle::addRoute(){
	shuttle::generateRoute "$@" >> $SWITCHBOARD
}

function shuttle::deleteRoute() {
	sed -i '/"${routeName}"/d' $SWITCHBOARD
}

shuttle::deleteRoute "$routeName"

# shuttle::addRoute "$@"

