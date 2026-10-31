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
	[ "$(routes)" = "zeta[]:$DIR_A"$'\n'"Alpha[]:$DIR_B" ]
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

# Writing the routes file (#1, #3)

@test "a symlinked routes file stays a symlink after every command" {
	mkdir -p "$(dirname "$ROUTES_FILE")" "$BATS_TEST_TMPDIR/dotfiles"
	local real="$BATS_TEST_TMPDIR/dotfiles/routes"
	printf '%s\n' "# shtl routes v1" > "$real"
	ln -s "$real" "$ROUTES_FILE"
	shtl add work "$DIR_A"
	shtl add home "$DIR_B"
	shtl update work "$DIR_B"
	shtl persist work
	shtl remove home
	[ -L "$ROUTES_FILE" ]
	[ "$(cat "$real")" = "# shtl routes v1"$'\n'"work[persist]:$DIR_B" ]
}

@test "a relative symlink to the routes file is followed" {
	mkdir -p "$(dirname "$ROUTES_FILE")"
	printf '%s\n' "# shtl routes v1" > "$(dirname "$ROUTES_FILE")/real-routes"
	ln -s real-routes "$ROUTES_FILE"
	shtl add work "$DIR_A"
	[ -L "$ROUTES_FILE" ]
	[ "$(routes)" = "work[]:$DIR_A" ]
}

@test "commands leave no temp files behind" {
	shtl add work "$DIR_A"
	shtl update work "$DIR_B"
	shtl persist work
	shtl remove work
	[ "$(ls -A "$(dirname "$ROUTES_FILE")")" = "routes" ]
}

@test "a leftover routes.tmp is not used or overwritten" {
	mkdir -p "$(dirname "$ROUTES_FILE")"
	printf '%s\n' "# shtl routes v1" > "$ROUTES_FILE"
	printf '%s\n' "someone else's write" > "$ROUTES_FILE.tmp"
	shtl add work "$DIR_A"
	[ "$(routes)" = "work[]:$DIR_A" ]
	[ "$(cat "$ROUTES_FILE.tmp")" = "someone else's write" ]
}

@test "writes work with noclobber on" {
	run env SHELLOPTS=noclobber shtl add work "$DIR_A"
	[ "$status" -eq 0 ]
	run env SHELLOPTS=noclobber shtl remove work
	[ "$status" -eq 0 ]
	[ -z "$(routes)" ]
}

@test "a failed write leaves the routes file as it was" {
	mkdir -p "$(dirname "$ROUTES_FILE")"
	printf '%s\n' "# shtl routes v1" "work[]:$DIR_A" > "$ROUTES_FILE"
	chmod a-w "$(dirname "$ROUTES_FILE")"
	run shtl remove work
	chmod u+w "$(dirname "$ROUTES_FILE")"
	[ "$status" -eq 1 ]
	[ "$(routes)" = "work[]:$DIR_A" ]
	[ "$(ls -A "$(dirname "$ROUTES_FILE")")" = "routes" ]
}

@test "rewrites keep the routes file's permissions" {
	mkdir -p "$(dirname "$ROUTES_FILE")"
	printf '%s\n' "# shtl routes v1" > "$ROUTES_FILE"
	chmod 644 "$ROUTES_FILE"
	shtl add work "$DIR_A"
	[ -n "$(find "$ROUTES_FILE" -perm 644)" ]
}

# Hand edits survive (#2)

@test "commands keep comments, blank lines and order" {
	mkdir -p "$(dirname "$ROUTES_FILE")"
	printf '%s\n' "# shtl routes v1" "" "# work stuff" "zz[]:$DIR_A" "aa[]:$DIR_A" "" "# other" "mm[]:$DIR_A" > "$ROUTES_FILE"
	shtl update zz "$DIR_B"
	shtl persist aa
	shtl remove mm
	shtl add new "$DIR_B"
	[ "$(cat "$ROUTES_FILE")" = "$(printf '%s\n' "# shtl routes v1" "" "# work stuff" "zz[]:$DIR_B" "aa[persist]:$DIR_A" "" "# other" "new[]:$DIR_B")" ]
}

@test "add starts a new line when the file doesn't end with one" {
	mkdir -p "$(dirname "$ROUTES_FILE")"
	printf '%s\n%s' "# shtl routes v1" "work[]:$DIR_A" > "$ROUTES_FILE"
	shtl add home "$DIR_B"
	[ "$(routes)" = "work[]:$DIR_A"$'\n'"home[]:$DIR_B" ]
}

@test "list is sorted even when the file isn't" {
	mkdir -p "$(dirname "$ROUTES_FILE")"
	printf '%s\n' "# shtl routes v1" "b[]:$DIR_A" "C[]:$DIR_A" "a[]:$DIR_A" > "$ROUTES_FILE"
	[ "$(shtl list --names | tr '\n' ' ')" = "a b C " ]
	run shtl list
	[ "${lines[0]}" = "a  $DIR_A" ]
}

# Home paths (#4)

@test "add stores paths in the home directory as ~/" {
	use_test_home
	mkdir -p "$HOME/work"
	shtl add work "$HOME/work"
	shtl add home "$HOME"
	shtl add other "$DIR_A"
	[ "$(routes)" = "work[]:~/work"$'\n'"home[]:~"$'\n'"other[]:$DIR_A" ]
}

@test "a ~/ route goes to the path under each machine's home" {
	mkdir -p "$(dirname "$ROUTES_FILE")" "$BATS_TEST_TMPDIR/mac/work" "$BATS_TEST_TMPDIR/linux/work"
	printf '%s\n' "# shtl routes v1" "work[]:~/work" "home[]:~" > "$ROUTES_FILE"
	run env HOME="$BATS_TEST_TMPDIR/mac" shtl path work
	[ "$output" = "$BATS_TEST_TMPDIR/mac/work" ]
	run env HOME="$BATS_TEST_TMPDIR/linux" shtl path work
	[ "$output" = "$BATS_TEST_TMPDIR/linux/work" ]
	run env HOME="$BATS_TEST_TMPDIR/linux" shtl path home
	[ "$output" = "$BATS_TEST_TMPDIR/linux" ]
}

@test "the shell function goes to a ~/ route" {
	use_test_home
	mkdir -p "$HOME/work"
	shtl add work "$HOME/work"
	run bash -c 'eval "$(shtl init)" && shtl work && pwd'
	[ "$output" = "$HOME/work" ]
}

@test "a directory that only starts like the home directory stays absolute" {
	use_test_home
	mkdir -p "$HOME" "$BATS_TEST_TMPDIR/homework"
	shtl add hw "$BATS_TEST_TMPDIR/homework"
	[ "$(routes)" = "hw[]:$BATS_TEST_TMPDIR/homework" ]
}

@test "add and update accept a quoted ~/ path" {
	use_test_home
	mkdir -p "$HOME/a" "$HOME/b"
	# shellcheck disable=SC2088 # shtl gets the literal ~, as from a quoted argument
	shtl add work '~/a'
	[ "$(routes)" = "work[]:~/a" ]
	# shellcheck disable=SC2088
	shtl update work '~/b'
	[ "$(routes)" = "work[]:~/b" ]
}

@test "list shows ~/ paths as stored" {
	use_test_home
	mkdir -p "$HOME/work"
	shtl add work "$HOME/work"
	run shtl list
	[ "$output" = "work  ~/work" ]
}

@test "persist and clean check the expanded ~/ path" {
	use_test_home
	mkdir -p "$HOME/work"
	shtl add work "$HOME/work" --persist
	run shtl persist work
	[ "$status" -eq 0 ]
	[ "$(routes)" = "work[]:~/work" ]
	run shtl clean
	[[ $output == *"All routes point to existing directories"* ]] || false
}

@test "doctor accepts ~ and ~/ paths but not ~user" {
	mkdir -p "$(dirname "$ROUTES_FILE")"
	printf '%s\n' "# shtl routes v1" "a[]:~" "b[]:~/work" "c[]:~bob/work" > "$ROUTES_FILE"
	run shtl doctor
	[ "$status" -eq 1 ]
	[[ $output != *"Line 2"* ]] || false
	[[ $output != *"Line 3"* ]] || false
	[[ $output == *"Line 4: path \"~bob/work\""* ]] || false
}
