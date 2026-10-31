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
	for name in add update remove rm list ls clean persist path doctor init help version; do
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

# Paths must be absolute

@test "add rejects relative paths" {
	cd "$DIR_A"
	for path in . .. ./x x/y; do
		run shtl add rel "$path"
		[ "$status" -eq 1 ]
		[[ $output == *"is not an absolute path"* ]]
	done
	[ -z "$(routes)" ]
}

@test "add removes extra slashes and dot segments from absolute paths" {
	shtl add work "$DIR_A//./"
	[ "$(routes)" = "work[]:$DIR_A" ]
}

@test "add --persist accepts a missing absolute path" {
	shtl add later "$MISSING_DIR" --persist
	[ "$(routes)" = "later[persist]:$MISSING_DIR" ]
}

@test "add rejects a missing directory without --persist" {
	run shtl add later "$MISSING_DIR"
	[ "$status" -eq 1 ]
	[[ $output == *"does not exist"*"--persist"* ]]
	[ -z "$(routes)" ]
}

@test "add --persist rejects relative paths" {
	run shtl add later not/yet --persist
	[ "$status" -eq 1 ]
	[ -z "$(routes)" ]
}

@test "add rejects a path that is a file, even with --persist" {
	touch "$BATS_TEST_TMPDIR/file"
	run shtl add cfg "$BATS_TEST_TMPDIR/file" --persist
	[ "$status" -eq 1 ]
	[[ $output == *"is not a directory"* ]]
	[ -z "$(routes)" ]
}

@test "add checks the normalized path, not the typed one" {
	ln -s "$DIR_A" "$BATS_TEST_TMPDIR/link"
	# The typed path exists through the symlink, but the stored path does not
	run shtl add r "$BATS_TEST_TMPDIR/link/../b/../missing"
	[ "$status" -eq 1 ]
	[ -z "$(routes)" ]
	# The typed path does not exist, but the stored path does
	run shtl add r "$MISSING_DIR/../a"
	[ "$status" -eq 0 ]
	[ "$(routes)" = "r[]:$DIR_A" ]
}

@test "add rejects a current directory that was deleted" {
	mkdir "$BATS_TEST_TMPDIR/gone"
	cd "$BATS_TEST_TMPDIR/gone"
	rmdir "$BATS_TEST_TMPDIR/gone"
	run shtl add here
	[ "$status" -eq 1 ]
	[[ $output == *"does not exist"* ]]
	[ -z "$(routes)" ]
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

@test "update rejects relative paths and leaves the route alone" {
	shtl add work "$DIR_A"
	cd "$DIR_A"
	run shtl update work ../b
	[ "$status" -eq 1 ]
	[[ $output == *"is not an absolute path"* ]]
	[ "$(routes)" = "work[]:$DIR_A" ]
}

@test "update keeps the route's flags" {
	shtl add work "$DIR_A" --persist
	shtl update work "$DIR_B"
	[ "$(routes)" = "work[persist]:$DIR_B" ]
}

@test "update rejects a missing directory for a route that is not persistent" {
	shtl add work "$DIR_A"
	run shtl update work "$MISSING_DIR"
	[ "$status" -eq 1 ]
	[[ $output == *"does not exist"*"shtl persist work. Then run this update again"* ]]
	[ "$(routes)" = "work[]:$DIR_A" ]
}

@test "update rejects a path that is a file" {
	shtl add work "$DIR_A" --persist
	touch "$BATS_TEST_TMPDIR/file"
	run shtl update work "$BATS_TEST_TMPDIR/file"
	[ "$status" -eq 1 ]
	[[ $output == *"is not a directory"* ]]
	[ "$(routes)" = "work[persist]:$DIR_A" ]
}

@test "update accepts a missing directory for a persistent route" {
	shtl add work "$DIR_A" --persist
	shtl update work "$MISSING_DIR"
	[ "$(routes)" = "work[persist]:$MISSING_DIR" ]
}

@test "update only touches the named route" {
	shtl add axb "$DIR_A"
	shtl add a.b "$DIR_A"
	shtl update a.b "$DIR_B"
	[ "$(routes)" = "axb[]:$DIR_A"$'\n'"a.b[]:$DIR_B" ]
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
	printf '%s\n' "# shtl routes v1" "update[]:$DIR_A" "work[]:$DIR_B" > "$ROUTES_FILE"
	run --separate-stderr shtl list
	[ "$status" -eq 0 ]
	[[ $stderr == *'Route "update" has the same name as a shtl command'* ]]
	[[ $stderr != *'"work"'* ]]
	run --separate-stderr shtl path update
	[ "$output" = "$DIR_A" ]
}

@test "list --names doesn't warn, since completion reads it" {
	mkdir -p "$(dirname "$ROUTES_FILE")"
	printf '%s\n' "# shtl routes v1" "update[]:$DIR_A" > "$ROUTES_FILE"
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
	mkdir "$MISSING_DIR"
	shtl add old "$MISSING_DIR"
	rmdir "$MISSING_DIR"
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
	[ "$(routes)" = "axb[]:$DIR_A"$'\n'"a.b[persist]:$DIR_B" ]
}

@test "persist won't turn off for a route whose directory is missing" {
	shtl add later "$MISSING_DIR" --persist
	run shtl persist later
	[ "$status" -eq 1 ]
	[[ $output == *"does not exist"*"shtl update later PATH"* ]]
	[ "$(routes)" = "later[persist]:$MISSING_DIR" ]
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

# Did you mean (#6)

@test "an unknown route lists the routes that start with it" {
	shtl add work "$DIR_A"
	shtl add Workshop "$DIR_B"
	shtl add home "$DIR_B"
	run shtl path wo
	[ "$status" -eq 1 ]
	[[ $output == *"Did you mean: Workshop, work"* || $output == *"Did you mean: work, Workshop"* ]] || false
	[[ $output != *"home"* ]] || false
}

@test "an unknown route with no prefix match suggests nothing" {
	shtl add work "$DIR_A"
	run shtl path zz
	[ "$status" -eq 1 ]
	[[ $output != *"Did you mean"* ]]
}

@test "shtl with an unknown name suggests routes instead of printing help" {
	shtl add work "$DIR_A"
	run shtl wo
	[ "$status" -eq 1 ]
	[[ $output == *"Did you mean: work"* ]] || false
	[[ $output != *"Usage:"* ]]
}

@test "shtl with an unknown name and no match still prints help" {
	run shtl zz
	[ "$status" -eq 1 ]
	[[ $output == *"Usage:"* ]]
}

@test "remove, update and persist suggest routes for an unknown name" {
	shtl add work "$DIR_A"
	for cmd in remove update persist; do
		run shtl "$cmd" wo
		[ "$status" -eq 1 ]
		[[ $output == *"Did you mean: work"* ]] || false
	done
}

@test "the shell function suggests routes and stays put" {
	shtl add work "$DIR_A"
	run bash -c 'cd "$1" && eval "$(shtl init)"; shtl wo; echo "status=$?"; pwd' _ "$DIR_B"
	[[ $output == *"Did you mean: work"* ]] || false
	[[ $output == *"status=1"* ]] || false
	[[ $output == *"$DIR_B" ]]
}

# Shared directories (#8)

@test "add warns when another route points to the same directory" {
	shtl add work "$DIR_A"
	run shtl add other "$DIR_A"
	[ "$status" -eq 0 ]
	[[ $output == *"WARN"*"Route \"work\" also points to $DIR_A"* ]] || false
	[ "$(routes)" = "work[]:$DIR_A"$'\n'"other[]:$DIR_A" ]
}

@test "update warns when another route points to the new directory" {
	shtl add work "$DIR_A"
	shtl add other "$DIR_B"
	run shtl update other "$DIR_A"
	[ "$status" -eq 0 ]
	[[ $output == *"Route \"work\" also points to $DIR_A"* ]]
}

@test "updating a route to its own directory doesn't warn" {
	shtl add work "$DIR_A"
	run shtl update work "$DIR_A"
	[ "$status" -eq 0 ]
	[[ $output != *"also points to"* ]]
}

@test "the shared directory warning compares ~/ paths expanded" {
	use_test_home
	mkdir -p "$HOME/work"
	mkdir -p "$(dirname "$ROUTES_FILE")"
	printf '%s\n' "# shtl routes v1" "work[]:~/work" > "$ROUTES_FILE"
	run shtl add other "$HOME/work"
	[[ $output == *"Route \"work\" also points to $HOME/work"* ]]
}
