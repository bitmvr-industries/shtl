#!/usr/bin/env bats

load test_helper

# add

@test "add stores a route with the given path" {
	run shtl add work "$DIR_A"
	[ "$status" -eq 0 ]
	[ "$(routes)" = "work:$DIR_A" ]
}

@test "add defaults to the current directory" {
	cd "$DIR_B"
	run shtl add here
	[ "$status" -eq 0 ]
	[ "$(routes)" = "here:$(pwd)" ]
}

@test "add --persist marks the route persistent" {
	run shtl add work "$DIR_A" --persist
	[ "$status" -eq 0 ]
	[ "$(routes)" = "work:$DIR_A:persist" ]
}

@test "add keeps routes sorted case-insensitively" {
	shtl add b "$DIR_A"
	shtl add C "$DIR_A"
	shtl add a "$DIR_A"
	[ "$(routes | cut -d: -f1 | tr '\n' ' ')" = "a b C " ]
}

@test "add rejects a duplicate name" {
	shtl add work "$DIR_A"
	run shtl add work "$DIR_B"
	[ "$status" -eq 1 ]
	[[ $output == *"already exists"* ]]
	[ "$(routes)" = "work:$DIR_A" ]
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
	for name in add remove rm list ls clean persist path init help version; do
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

# remove

@test "remove deletes only the named route" {
	shtl add axb "$DIR_A"
	shtl add a.b "$DIR_B"
	run shtl remove a.b
	[ "$status" -eq 0 ]
	[ "$(routes)" = "axb:$DIR_A" ]
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

@test "list prints every route entry" {
	shtl add a "$DIR_A"
	shtl add b "$DIR_B" --persist
	run shtl ls
	[ "$status" -eq 0 ]
	[ "$output" = "a:$DIR_A"$'\n'"b:$DIR_B:persist" ]
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
	[ "$(routes)" = "work:$DIR_A:persist" ]

	run shtl persist work
	[[ $output == *"no longer persistent"* ]]
	[ "$(routes)" = "work:$DIR_A" ]
}

@test "persist only touches the named route" {
	shtl add axb "$DIR_A"
	shtl add a.b "$DIR_B"
	shtl persist a.b
	[ "$(routes)" = "a.b:$DIR_B:persist"$'\n'"axb:$DIR_A" ]
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
