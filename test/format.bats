#!/usr/bin/env bats

load test_helper

# The routes file format: a header line, then NAME[FLAGS]:PATH entries

@test "a new routes file starts with the header" {
	run shtl list
	[ "$(head -n 1 "$ROUTES_FILE")" = "# shtl routes v1" ]
}

@test "the header stays first after adding routes" {
	shtl add zeta "$DIR_A"
	shtl add Alpha "$DIR_B"
	[ "$(head -n 1 "$ROUTES_FILE")" = "# shtl routes v1" ]
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
	printf '%s\n' "# shtl routes v1" "work[other]:$DIR_A" > "$ROUTES_FILE"
	shtl persist work
	[ "$(routes)" = "work[other,persist]:$DIR_A" ]
	shtl persist work
	[ "$(routes)" = "work[other]:$DIR_A" ]
}

@test "hand-added blank lines and comments are ignored" {
	mkdir -p "$(dirname "$ROUTES_FILE")"
	printf '%s\n' "# shtl routes v1" "" "# my work stuff" "work[]:$DIR_A" "   " > "$ROUTES_FILE"
	run shtl list --names
	[ "$output" = "work" ]
}

@test "a routes file from a newer shtl is left alone" {
	mkdir -p "$(dirname "$ROUTES_FILE")"
	printf '%s\n' "# shtl routes v2" "something new" > "$ROUTES_FILE"
	run shtl list
	[ "$status" -eq 1 ]
	[[ $output == *"newer version of shtl (v2)"* ]]
	[ "$(cat "$ROUTES_FILE")" = "# shtl routes v2"$'\n'"something new" ]
}

@test "a routes file without the header is left alone" {
	mkdir -p "$(dirname "$ROUTES_FILE")"
	printf '%s\n' "work:/tmp" > "$ROUTES_FILE"
	run shtl list
	[ "$status" -eq 1 ]
	[[ $output == *"is not a shtl routes file"* ]]
	[ "$(cat "$ROUTES_FILE")" = "work:/tmp" ]
}
