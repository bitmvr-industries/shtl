#!/usr/bin/env bash

source lib/shtl_functions.sh

shtl_init

if [[ ! $1 ]]; then
	shtl_usage
fi

while (( "$#" ));  do
	case $1 in
		-l|--list)
			shtl_list_routes
			break
			;;	
		-a|--add)
			shift
			persist=""
			routeArgs=()
			for arg in "$@"; do
				case $arg in
					-p|--persist) persist="persist" ;;
					*) routeArgs+=("$arg") ;;
				esac
			done
			shtl_validate_arguments "${routeArgs[@]}"
			shtl_add_route "${routeArgs[0]}" "${routeArgs[1]}" "$persist"
			break
			;;
		-c|--clean)
			shtl_clean_routes
			break
			;;
		-p|--persist)
			shift
			shtl_validate_arguments "$@"
			shtl_toggle_persist "$1"
			break
			;;
		-d|--delete)
			shift
			shtl_validate_arguments "$@"
			shtl_delete_route "$1"
			break
			;;
		-h|--help)
			shtl_usage
			break
			;;
		-m|--modify)
			#TODO
			shtl_modify_route_name
			break
			;;
		-v|--version)
			shtl_version
			break
			;;
		--path)
			shift
			shtl_validate_arguments "$@"
			shtl_print_path "$1"
			exit
			;;
		--names)
			shtl_get_route_names
			break
			;;
		init)
			shtl_print_init
			break
			;;
		*)
			if shtl_route_name_exists "$1"; then
				shtl_route "$1"
				exit
			else
				shtl_log "ERROR" "The supplied flag or route name is invalid"
				shtl_usage
				exit 1
      fi
      break
			;;
	esac
done
