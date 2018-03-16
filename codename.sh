#!/usr/bin/env bash


# Route Argument
routeName="${1}"

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

#if [ "$#" -eq 0 ]; then
#	echo "No arguments were passed"
#	echo " "
#	echo "$(usage)"
#fi

function shuttle::getRouteEntry() {
	grep "$routeName" "$SWITCHBOARD"
}

function shuttle::getRoute() {
	route=$(shuttle::getRouteEntry)
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

function addRoute() {	
	currentDir="$(shuttle::getCurrentPath)"
	providedPath="$2"
	route="${providedPath:$currentDir}"
	echo $providedPath
	echo $currentDir
	echo $route
}

shuttle::getRouteEntry
