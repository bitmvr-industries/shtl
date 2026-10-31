#!/usr/bin/env bats

# shtl's interactive clean screen, driven with expect

load test_helper

# Runs shtl clean in a terminal, waits for the list, types $1 (expect
# escapes, e.g. "\r" for Enter), then prints shtl's output and exit status
clean_typing() {
	command -v expect > /dev/null || skip "expect not installed"
	# shellcheck disable=SC2016 # $ expressions are for expect
	SHTL_KEYS="$1" expect -c '
		set timeout 5
		log_user 1
		spawn shtl clean
		expect "selected"
		send -- [subst -nocommands -novariables $env(SHTL_KEYS)]
		expect eof
		puts "status=[lindex [wait] 3]"'
}

# Two routes on this host to missing directories, one shared with another
# host, and one that exists
missing_routes() {
	add_route gone "$BATS_TEST_TMPDIR/gone" "$(this_host)"
	printf '\n[[route]]\nname = "shared"\npath = "/no/such/dir"\nhosts = ["not-this-host", "%s"]\n' "$(this_host)" >> "$ROUTES_FILE"
	add_route here "$DIR_A" "$(this_host)"
}

@test "clean lists the routes to missing directories, all selected" {
	missing_routes
	run clean_typing "q"
	[[ $output == *"[x] gone"* && $output == *"[x] shared"* ]] || false
	[[ $output != *"] here"* ]] || false
	[[ $output == *"2 selected"* ]] || false
}

@test "clean removes the selected routes for this host only" {
	missing_routes
	run clean_typing "\r"
	[[ $output == *"Removed 2 route(s)"* && $output == *"status=0"* ]] || false
	run shtl list --names
	[ "$output" = "here" ]
	grep -q 'hosts = \["not-this-host"\]' "$ROUTES_FILE"
	run grep -q 'name = "gone"' "$ROUTES_FILE"
	[ "$status" -ne 0 ]
}

@test "clean space deselects the route under the cursor" {
	missing_routes
	run clean_typing " \r"
	[[ $output == *"Removed 1 route(s)"* ]] || false
	run shtl list --names
	[ "$output" = "$(printf 'gone\nhere')" ]
}

@test "clean moves with j and k" {
	missing_routes
	run clean_typing "j \r"
	[[ $output == *"Removed 1 route(s)"* ]] || false
	run shtl list --names
	[ "$output" = "$(printf 'here\nshared')" ]
}

@test "clean moves with the arrow keys" {
	missing_routes
	run clean_typing "\x1b\[B\x1b\[B\x1b\[A \r"
	[[ $output == *"Removed 1 route(s)"* ]] || false
	run shtl list --names
	[ "$output" = "$(printf 'gone\nhere')" ]
}

@test "clean a deselects all, then selects all" {
	missing_routes
	run clean_typing "a\r"
	[[ $output == *"Removed 0 route(s)"* ]] || false
	run clean_typing "aa\r"
	[[ $output == *"Removed 2 route(s)"* ]] || false
}

@test "clean q cancels and changes nothing" {
	missing_routes
	cp "$ROUTES_FILE" "$BATS_TEST_TMPDIR/before"
	run clean_typing "q"
	[[ $output == *"Clean cancelled. No routes were removed"* && $output == *"status=0"* ]] || false
	cmp "$ROUTES_FILE" "$BATS_TEST_TMPDIR/before"
}

@test "clean Ctrl-C exits 130 and changes nothing" {
	missing_routes
	cp "$ROUTES_FILE" "$BATS_TEST_TMPDIR/before"
	run clean_typing "\x03"
	[[ $output == *"status=130"* ]] || false
	cmp "$ROUTES_FILE" "$BATS_TEST_TMPDIR/before"
}
