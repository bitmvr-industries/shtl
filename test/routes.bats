#!/usr/bin/env bats

load test_helper

# add

@test "add stores a route with the given path" {
	run shtl add work "$DIR_A"
	[ "$status" -eq 0 ]
	[ "$(routes)" = "work[]:$DIR_A" ]
}

@test "add defaults to the current directory" {
	cd "$DIR_B"
	run shtl add here
	[ "$status" -eq 0 ]
	[ "$(routes)" = "here[]:$(pwd)" ]
}

@test "add --persist marks the route persistent" {
	run shtl add work "$DIR_A" --persist
	[ "$status" -eq 0 ]
	[ "$(routes)" = "work[persist]:$DIR_A" ]
}

@test "add keeps routes sorted case-insensitively" {
	shtl add b "$DIR_A"
	shtl add C "$DIR_A"
	shtl add a "$DIR_A"
	shtl add ab "$DIR_A"
	[ "$(shtl list --names | tr '\n' ' ')" = "a ab b C " ]
}

@test "add rejects a duplicate name" {
	shtl add work "$DIR_A"
	run shtl add work "$DIR_B"
	[ "$status" -eq 1 ]
	[[ $output == *"already exists"* ]]
	[ "$(routes)" = "work[]:$DIR_A" ]
}

@test "add requires a name" {
	run shtl add
	[ "$status" -eq 1 ]
	[[ $output == *"Please provide a route name"* ]]
}

@test "add rejects names with a colon" {
	run shtl add 'foo:bar' "$DIR_A"
	[ "$status" -eq 1 ]
	[ -z "$(routes)" ]
}

@test "add rejects names starting with a dash" {
	run shtl add -- -x "$DIR_A"
	[ "$status" -eq 1 ]
	[ -z "$(routes)" ]
}

@test "add rejects names that are subcommands" {
	for name in add update remove rm list ls clean persist path init help version; do
		run shtl add "$name" "$DIR_A"
		[ "$status" -eq 1 ]
	done
	[ -z "$(routes)" ]
}

# Names are matched literally, not as regexes

@test "names with regex characters don't match other routes" {
	shtl add axb "$DIR_A"
	run shtl add a.b "$DIR_B"
	[ "$status" -eq 0 ]
	run shtl path a.b
	[ "$output" = "$DIR_B" ]
	run shtl path axb
	[ "$output" = "$DIR_A" ]
}

@test "numeric-looking names are compared as strings" {
	shtl add 1 "$DIR_A"
	run shtl add 01 "$DIR_B"
	[ "$status" -eq 0 ]
	run shtl path 01
	[ "$output" = "$DIR_B" ]
}

@test "names with glob characters and backslashes work" {
	shtl add 'w*' "$DIR_A"
	shtl add 'x\y' "$DIR_B"
	run shtl path 'w*'
	[ "$output" = "$DIR_A" ]
	run shtl path 'x\y'
	[ "$output" = "$DIR_B" ]
}

# Relative paths are stored as absolute paths

@test "add stores relative paths as absolute paths" {
	cd "$DIR_A"
	shtl add dot .
	shtl add parent ..
	shtl add sub ./x/../y/
	[ "$(routes)" = "dot[]:$DIR_A"$'\n'"parent[]:$BATS_TEST_TMPDIR"$'\n'"sub[]:$DIR_A/y" ]
}

@test "add removes extra slashes and dot segments from absolute paths" {
	shtl add work "$DIR_A//./"
	[ "$(routes)" = "work[]:$DIR_A" ]
}

@test "add stores a missing relative path as absolute with --persist" {
	cd "$DIR_A"
	shtl add later not/yet --persist
	[ "$(routes)" = "later[persist]:$DIR_A/not/yet" ]
}

# update

@test "update points a route at a new path" {
	shtl add work "$DIR_A"
	run shtl update work "$DIR_B"
	[ "$status" -eq 0 ]
	[[ $output == *"now points to $DIR_B"* ]]
	[ "$(routes)" = "work[]:$DIR_B" ]
}

@test "update defaults to the current directory" {
	shtl add work "$DIR_A"
	cd "$DIR_B"
	shtl update work
	[ "$(routes)" = "work[]:$DIR_B" ]
}

@test "update stores relative paths as absolute paths" {
	shtl add work "$DIR_A"
	cd "$DIR_A"
	shtl update work ../b
	[ "$(routes)" = "work[]:$DIR_B" ]
}

@test "update keeps the route's flags" {
	shtl add work "$DIR_A" --persist
	shtl update work "$DIR_B"
	[ "$(routes)" = "work[persist]:$DIR_B" ]
}

@test "update only touches the named route" {
	shtl add axb "$DIR_A"
	shtl add a.b "$DIR_A"
	shtl update a.b "$DIR_B"
	[ "$(routes)" = "a.b[]:$DIR_B"$'\n'"axb[]:$DIR_A" ]
}

@test "update fails for an unknown route" {
	run shtl update nope "$DIR_A"
	[ "$status" -eq 1 ]
	[[ $output == *"does not exist"* ]]
	[ -z "$(routes)" ]
}

@test "update requires a name" {
	run shtl update
	[ "$status" -eq 1 ]
	[[ $output == *"Please provide a route name"* ]]
}

# remove

@test "remove deletes only the named route" {
	shtl add axb "$DIR_A"
	shtl add a.b "$DIR_B"
	run shtl remove a.b
	[ "$status" -eq 0 ]
	[ "$(routes)" = "axb[]:$DIR_A" ]
}

@test "rm is an alias for remove" {
	shtl add work "$DIR_A"
	run shtl rm work
	[ "$status" -eq 0 ]
	[ -z "$(routes)" ]
}

@test "remove fails for an unknown route" {
	run shtl remove nope
	[ "$status" -eq 1 ]
	[[ $output == *"does not exist"* ]]
}

# list

@test "list explains when there are no routes" {
	run shtl list
	[ "$status" -eq 0 ]
	[[ $output == *"No routes yet"* ]]
}

@test "list prints names and paths in columns, marking persistent routes" {
	shtl add a "$DIR_A"
	shtl add longer "$DIR_B" --persist
	run --separate-stderr shtl ls
	[ "$status" -eq 0 ]
	[ "$output" = "a       $DIR_A"$'\n'"longer  $DIR_B  (persist)" ]
}

@test "list warns about routes named after a command" {
	mkdir -p "$(dirname "$ROUTES_FILE")"
	printf '%s\n' "# shtl routes v2" "update[]:$DIR_A" "work[]:$DIR_B" > "$ROUTES_FILE"
	run --separate-stderr shtl list
	[ "$status" -eq 0 ]
	[[ $stderr == *'Route "update" has the same name as a shtl command'* ]]
	[[ $stderr != *'"work"'* ]]
	run --separate-stderr shtl path update
	[ "$output" = "$DIR_A" ]
}

@test "list --names doesn't warn, since completion reads it" {
	mkdir -p "$(dirname "$ROUTES_FILE")"
	printf '%s\n' "# shtl routes v2" "update[]:$DIR_A" > "$ROUTES_FILE"
	run --separate-stderr shtl list --names
	[ "$output" = "update" ]
	[ -z "$stderr" ]
}

@test "list --names prints only names" {
	shtl add a "$DIR_A"
	shtl add b "$DIR_B" --persist
	run shtl list --names
	[ "$output" = "a"$'\n'"b" ]
}

# path

@test "path prints only the route's path on stdout" {
	shtl add work "$DIR_A"
	run --separate-stderr shtl path work
	[ "$status" -eq 0 ]
	[ "$output" = "$DIR_A" ]
	[ -z "$stderr" ]
}

@test "path strips the persist marker" {
	shtl add work "$DIR_A" --persist
	run shtl path work
	[ "$output" = "$DIR_A" ]
}

@test "path fails for an unknown route" {
	run shtl path nope
	[ "$status" -eq 1 ]
	[[ $output == *"does not exist"* ]]
}

@test "path fails when the directory is gone" {
	shtl add old "$MISSING_DIR"
	run --separate-stderr shtl path old
	[ "$status" -eq 1 ]
	[ -z "$output" ]
	[[ $stderr == *"doesn't exist"* ]]
}

# persist

@test "persist toggles the persist marker on and off" {
	shtl add work "$DIR_A"
	run shtl persist work
	[ "$status" -eq 0 ]
	[[ $output == *"now persistent"* ]]
	[ "$(routes)" = "work[persist]:$DIR_A" ]

	run shtl persist work
	[[ $output == *"no longer persistent"* ]]
	[ "$(routes)" = "work[]:$DIR_A" ]
}

@test "persist only touches the named route" {
	shtl add axb "$DIR_A"
	shtl add a.b "$DIR_B"
	shtl persist a.b
	[ "$(routes)" = "a.b[persist]:$DIR_B"$'\n'"axb[]:$DIR_A" ]
}

@test "persist fails for an unknown route" {
	run shtl persist nope
	[ "$status" -eq 1 ]
	[[ $output == *"does not exist"* ]]
}

# Running a route without the shell function

@test "shtl ROUTE prints the path and warns about the shell function" {
	shtl add work "$DIR_A"
	run --separate-stderr shtl work
	[ "$status" -eq 0 ]
	[ "$output" = "$DIR_A" ]
	[[ $stderr == *"shell function"* ]]
}

@test "shtl with an unknown command or route fails" {
	run shtl nope
	[ "$status" -eq 1 ]
	[[ $output == *"is not a shtl command or route"* ]]
}
