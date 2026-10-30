#!/usr/bin/env bats

load test_helper

# The routes file format: a header line, then NAME[FLAGS]:PATH entries

@test "a new routes file starts with the header" {
	run shtl list
	[ "$(head -n 1 "$ROUTES_FILE")" = "# shtl routes v2" ]
}

@test "the header stays first after adding routes" {
	shtl add zeta "$DIR_A"
	shtl add Alpha "$DIR_B"
	[ "$(head -n 1 "$ROUTES_FILE")" = "# shtl routes v2" ]
	[ "$(routes)" = "Alpha[]:$DIR_B"$'\n'"zeta[]:$DIR_A" ]
}

@test "paths can contain colons" {
	mkdir -p "$BATS_TEST_TMPDIR/a:b"
	shtl add colon "$BATS_TEST_TMPDIR/a:b"
	run shtl path colon
	[ "$output" = "$BATS_TEST_TMPDIR/a:b" ]
}

@test "a path ending in :persist is just a path" {
	mkdir -p "$BATS_TEST_TMPDIR/dir:persist"
	shtl add odd "$BATS_TEST_TMPDIR/dir:persist"
	run shtl path odd
	[ "$output" = "$BATS_TEST_TMPDIR/dir:persist" ]
	run --separate-stderr shtl list
	[[ $output != *"(persist)"* ]]
}

@test "add rejects names with brackets or a leading #" {
	for name in 'a[b' 'a]b' '#x'; do
		run shtl add "$name" "$DIR_A"
		[ "$status" -eq 1 ]
	done
	[ -z "$(routes)" ]
}

@test "persist keeps other flags" {
	mkdir -p "$(dirname "$ROUTES_FILE")"
	printf '%s\n' "# shtl routes v2" "work[other]:$DIR_A" > "$ROUTES_FILE"
	shtl persist work
	[ "$(routes)" = "work[other,persist]:$DIR_A" ]
	shtl persist work
	[ "$(routes)" = "work[other]:$DIR_A" ]
}

@test "hand-added blank lines and comments are ignored" {
	mkdir -p "$(dirname "$ROUTES_FILE")"
	printf '%s\n' "# shtl routes v2" "" "# my work stuff" "work[]:$DIR_A" "   " > "$ROUTES_FILE"
	run shtl list --names
	[ "$output" = "work" ]
}

# Migrating from the original NAME:PATH[:persist] format

@test "migration converts old entries and keeps a backup" {
	write_v1_routes "work:$DIR_A" "nas:$DIR_B:persist" "" "odd:/tmp/a:b"
	run --separate-stderr shtl list --names
	[ "$status" -eq 0 ]
	[[ $stderr == *"Updated"*"routes.v1.bak"* ]]
	[ "$(head -n 1 "$ROUTES_FILE")" = "# shtl routes v2" ]
	[ "$(routes)" = "nas[persist]:$DIR_B"$'\n'"odd[]:/tmp/a:b"$'\n'"work[]:$DIR_A" ]
	[ "$(cat "$ROUTES_FILE.v1.bak")" = "work:$DIR_A"$'\n'"nas:$DIR_B:persist"$'\n'$'\n'"odd:/tmp/a:b" ]
}

@test "migration happens once" {
	write_v1_routes "work:$DIR_A"
	shtl list
	run --separate-stderr shtl list
	[ -z "$stderr" ]
	[ "$(routes)" = "work[]:$DIR_A" ]
}

@test "migrated routes work with every command" {
	write_v1_routes "work:$DIR_A" "nas:$MISSING_DIR:persist"
	# The first run migrates; its notice goes to stderr, leaving stdout clean
	run --separate-stderr shtl path work
	[ "$output" = "$DIR_A" ]
	run shtl clean
	[[ $output == *"All routes point to existing directories"* ]]
	shtl persist nas
	[ "$(routes)" = "nas[]:$MISSING_DIR"$'\n'"work[]:$DIR_A" ]
}

@test "an empty old file gets the header without a backup" {
	write_v1_routes ""
	run --separate-stderr shtl list
	[ "$status" -eq 0 ]
	[[ $stderr != *"Updated"* ]]
	[ "$(cat "$ROUTES_FILE")" = "# shtl routes v2" ]
	[ ! -e "$ROUTES_FILE.v1.bak" ]
}

@test "migration refuses names it can't convert and changes nothing" {
	write_v1_routes "work:$DIR_A" "a[1]:$DIR_B" "nocolon"
	run shtl list
	[ "$status" -eq 1 ]
	[[ $output == *"a[1]:$DIR_B"* ]]
	[[ $output == *"nocolon"* ]]
	[ "$(cat "$ROUTES_FILE")" = "work:$DIR_A"$'\n'"a[1]:$DIR_B"$'\n'"nocolon" ]
	[ ! -e "$ROUTES_FILE.v1.bak" ]
}

@test "a routes file from a newer shtl is left alone" {
	mkdir -p "$(dirname "$ROUTES_FILE")"
	printf '%s\n' "# shtl routes v3" "something new" > "$ROUTES_FILE"
	run shtl list
	[ "$status" -eq 1 ]
	[[ $output == *"newer version of shtl (v3)"* ]]
	[ "$(cat "$ROUTES_FILE")" = "# shtl routes v3"$'\n'"something new" ]
}
