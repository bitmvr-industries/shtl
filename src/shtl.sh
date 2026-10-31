#!/usr/bin/env bash

source lib/shtl_functions.sh

subcommand="$1"
shift

# These don't read the routes file, so a bad one can't stop them
case $subcommand in
	""|help|init|version) ;;
	*) shtl_init ;;
esac

case $subcommand in
	""|help)
		shtl_usage
		;;
	add)
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
		;;
	update)
		shtl_validate_arguments "$@"
		shtl_update_route "$1" "$2"
		;;
	remove|rm)
		shtl_validate_arguments "$@"
		shtl_delete_route "$1"
		;;
	list|ls)
		if [[ $1 == --names ]]; then
			shtl_get_route_names
		else
			shtl_list_routes
		fi
		;;
	clean)
		shtl_clean_routes
		;;
	persist)
		shtl_validate_arguments "$@"
		shtl_toggle_persist "$1"
		;;
	path)
		shtl_validate_arguments "$@"
		shtl_print_path "$1"
		;;
	init)
		shtl_print_init
		;;
	version)
		shtl_version
		;;
	*)
		if shtl_route_name_exists "$subcommand"; then
			shtl_route "$subcommand"
		else
			shtl_log "ERROR" "\"${subcommand}\" is not a shtl command or route"
			shtl_usage
			exit 1
		fi
		;;
esac
