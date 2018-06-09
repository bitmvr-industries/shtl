#!/usr/bin/env bash

source lib/shtl_functions.sh

if [[ ! $1 ]]; then
	shuttle::usage
fi

while (( "$#" ));  do
	case $1 in
		-l|--list)
			shuttle::listRoutes
			break
			;;	
		-a|--add)
			shift
			shuttle::validateArguments "$@"
			shuttle::addRoute "$1" "$2"
			break
			;;
		-d|--delete)
			shift
			shuttle::validateArguments "$@"
			shuttle::deleteRoute "$1"
			break
			;;
		-h|--help)
			shuttle::usage
			break
			;;
		-m|--modify)
			#TODO
			shuttle::modifyRouteName
			break
			;;
		-v|--version)
			shuttle::version
			break
			;;
		*)
			if shuttle::routeNameExists "$1"; then
				shuttle::route "$1"
			else
				shuttle::log "ERROR" "The supplied flag or route name is invalid"
				shuttle::usage
      fi
      break
			;;
	esac
done
