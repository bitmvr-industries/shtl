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

@test "a routes file with a different header is left alone" {
	mkdir -p "$(dirname "$ROUTES_FILE")"
	printf '%s\n' "# shtl routes" "work[]:/tmp" > "$ROUTES_FILE"
	run shtl list
	[ "$status" -eq 1 ]
	[[ $output == *"is not a shtl routes file"* ]]
	[ "$(cat "$ROUTES_FILE")" = "# shtl routes"$'\n'"work[]:/tmp" ]
}

@test "help, version and init work with a bad routes file" {
	mkdir -p "$(dirname "$ROUTES_FILE")"
	printf '%s\n' "work:/tmp" > "$ROUTES_FILE"
	run shtl help
	[ "$status" -eq 0 ]
	run shtl version
	[ "$status" -eq 0 ]
	run shtl init
	[ "$status" -eq 0 ]
	[ "$(cat "$ROUTES_FILE")" = "work:/tmp" ]
}

@test "a routes file without the header is left alone" {
	mkdir -p "$(dirname "$ROUTES_FILE")"
	printf '%s\n' "work:/tmp" > "$ROUTES_FILE"
	run shtl list
	[ "$status" -eq 1 ]
	[[ $output == *"is not a shtl routes file"* ]]
	[ "$(cat "$ROUTES_FILE")" = "work:/tmp" ]
}

# doctor

@test "doctor passes a good routes file" {
	mkdir -p "$(dirname "$ROUTES_FILE")"
	printf '%s\n' "# shtl routes v1" "" "# a comment" "nas[persist]:/Volumes/nas" "work[]:/a:b c" > "$ROUTES_FILE"
	run shtl doctor
	[ "$status" -eq 0 ]
	[[ $output == "No problems found"* ]]
}

@test "doctor passes when there is no routes file" {
	run shtl doctor
	[ "$status" -eq 0 ]
	[ ! -f "$ROUTES_FILE" ]
}

@test "doctor finds Windows line endings and trailing spaces" {
	mkdir -p "$(dirname "$ROUTES_FILE")"
	printf '%s\r\n' "# shtl routes v1" "work[]:/tmp" > "$ROUTES_FILE"
	printf '%s\n' "home[]:/tmp " >> "$ROUTES_FILE"
	run shtl doctor
	[ "$status" -eq 1 ]
	[[ $output == *"Line 1: has a Windows line ending"* ]]
	[[ $output == *"Line 2: has a Windows line ending"* ]]
	[[ $output == *"Line 3: ends with spaces or tabs"* ]]
	[[ $output != *"Line 1: must be"* ]]
}

@test "doctor finds a wrong header" {
	mkdir -p "$(dirname "$ROUTES_FILE")"
	printf '%s\n' "# shtl routes" "work[]:/tmp" > "$ROUTES_FILE"
	run shtl doctor
	[ "$status" -eq 1 ]
	[[ $output == *"Line 1: must be: # shtl routes v1"* ]]
}

@test "doctor finds malformed lines, bad flags and relative paths" {
	mkdir -p "$(dirname "$ROUTES_FILE")"
	printf '%s\n' "# shtl routes v1" "work:/tmp" "a[nope]:/tmp" "b[persist,]:/tmp" "c[]:tmp" "d[]:" > "$ROUTES_FILE"
	run shtl doctor
	[ "$status" -eq 1 ]
	[[ $output == *"Line 2: is not a route in the format NAME[FLAGS]:PATH"* ]]
	[[ $output == *"Line 3: \"nope\" is not a flag"* ]]
	[[ $output != *"Line 4:"* ]]
	[[ $output == *"Line 5: path \"tmp\" is not absolute"* ]]
	[[ $output == *"Line 6: path \"\" is not absolute"* ]]
}

@test "doctor finds bad, duplicate and command route names" {
	mkdir -p "$(dirname "$ROUTES_FILE")"
	printf '%s\n' "# shtl routes v1" "work[]:/tmp" "list[]:/tmp" "-x[]:/tmp" "[]:/tmp" "work[]:/var" > "$ROUTES_FILE"
	run shtl doctor
	[ "$status" -eq 1 ]
	[[ $output == *"Line 3: route name \"list\" is a shtl command"* ]]
	[[ $output == *"Line 4: route name \"-x\" is not valid"* ]]
	[[ $output == *"Line 5: route name \"\" is not valid"* ]]
	[[ $output == *"Line 6: route name \"work\" is also on line 2"* ]]
}

@test "doctor doesn't change the routes file" {
	mkdir -p "$(dirname "$ROUTES_FILE")"
	printf '%s\n' "# shtl routes" "zz[]:/tmp" "aa[]:/tmp" > "$ROUTES_FILE"
	run shtl doctor
	[ "$(cat "$ROUTES_FILE")" = "# shtl routes"$'\n'"zz[]:/tmp"$'\n'"aa[]:/tmp" ]
}

@test "the bad header error points to doctor" {
	mkdir -p "$(dirname "$ROUTES_FILE")"
	printf '%s\n' "# shtl routes v1 " > "$ROUTES_FILE"
	run shtl list
	[ "$status" -eq 1 ]
	[[ $output == *"run: shtl doctor"* ]]
}
