#!/usr/bin/env bats

# install.sh, the curl install. Fake curl and uname commands serve release
# files from a local directory, so the tests don't use the network.

bats_require_minimum_version 1.5.0

setup() {
	REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
	export HOME="$BATS_TEST_TMPDIR/home"
	mkdir -p "$HOME"
	export RELEASE_DIR="$BATS_TEST_TMPDIR/release"
	mkdir -p "$RELEASE_DIR"

	# Fake commands: uname prints $FAKE_OS / $FAKE_ARCH, and curl copies
	# the file named at the end of the URL from $RELEASE_DIR
	FAKE_BIN="$BATS_TEST_TMPDIR/bin"
	mkdir -p "$FAKE_BIN"
	cat > "$FAKE_BIN/uname" <<-'EOF'
		#!/bin/sh
		case "$1" in
			-s) echo "$FAKE_OS" ;;
			-m) echo "$FAKE_ARCH" ;;
		esac
	EOF
	cat > "$FAKE_BIN/curl" <<-'EOF'
		#!/bin/sh
		out=""
		while [ $# -gt 0 ]; do
			case "$1" in
				-o) out="$2"; shift ;;
				-*) ;;
				*) url="$1" ;;
			esac
			shift
		done
		echo "$url" >> "$RELEASE_DIR/requests"
		cp "$RELEASE_DIR/${url##*/}" "$out" 2> /dev/null || { echo "curl: (22) 404" >&2; exit 22; }
	EOF
	chmod +x "$FAKE_BIN/uname" "$FAKE_BIN/curl"
	PATH="$FAKE_BIN:$PATH"

	for name in darwin-arm64 linux-amd64 linux-arm64; do
		release_file "$name"
	done
	(cd "$RELEASE_DIR" && checksum shtl-*.tar.gz > checksums.txt)
}

checksum() {
	if command -v sha256sum > /dev/null; then
		sha256sum "$@"
	else
		shasum -a 256 "$@"
	fi
}

# A release tarball whose shtl prints the build name: release_file OS-ARCH
release_file() {
	local dir="$BATS_TEST_TMPDIR/build-$1"
	mkdir -p "$dir"
	printf '#!/bin/sh\necho "fake shtl %s"\n' "$1" > "$dir/shtl"
	chmod +x "$dir/shtl"
	echo "fake page $1" > "$dir/shtl.1"
	tar -czf "$RELEASE_DIR/shtl-$1.tar.gz" -C "$dir" shtl shtl.1
}

install_on() {
	FAKE_OS="$1" FAKE_ARCH="$2" run sh "$REPO_DIR/install.sh"
}

@test "install picks the Linux amd64 build" {
	install_on Linux x86_64
	[ "$status" -eq 0 ]
	[ "$("$HOME/.local/bin/shtl")" = "fake shtl linux-amd64" ]
}

@test "install picks the Linux arm64 build" {
	install_on Linux aarch64
	[ "$status" -eq 0 ]
	[ "$("$HOME/.local/bin/shtl")" = "fake shtl linux-arm64" ]
}

@test "install picks the macOS arm64 build" {
	install_on Darwin arm64
	[ "$status" -eq 0 ]
	[ "$("$HOME/.local/bin/shtl")" = "fake shtl darwin-arm64" ]
}

@test "install adds the manual page where man finds it" {
	install_on Linux x86_64
	[ "$status" -eq 0 ]
	[ "$(cat "$HOME/.local/share/man/man1/shtl.1")" = "fake page linux-amd64" ]
	[[ $output == *"man shtl"* ]] || false
}

@test "install replaces an older manual page" {
	mkdir -p "$HOME/.local/share/man/man1"
	echo old > "$HOME/.local/share/man/man1/shtl.1"
	install_on Linux x86_64
	[ "$(cat "$HOME/.local/share/man/man1/shtl.1")" = "fake page linux-amd64" ]
}

@test "install adds no manual page when the checksum is wrong" {
	release_file linux-amd64-other
	mv "$RELEASE_DIR/shtl-linux-amd64-other.tar.gz" "$RELEASE_DIR/shtl-linux-amd64.tar.gz"
	install_on Linux x86_64
	[ "$status" -eq 1 ]
	[ ! -e "$HOME/.local/share/man/man1/shtl.1" ]
}

@test "install downloads from the latest release" {
	install_on Linux x86_64
	grep -qx "https://github.com/bitmvr-industries/shtl/releases/latest/download/shtl-linux-amd64.tar.gz" "$RELEASE_DIR/requests"
	grep -qx "https://github.com/bitmvr-industries/shtl/releases/latest/download/checksums.txt" "$RELEASE_DIR/requests"
}

@test "install says there is no build for macOS on Intel" {
	install_on Darwin x86_64
	[ "$status" -eq 1 ]
	[[ $output == *"No shtl build for Darwin x86_64"* ]] || false
	[[ $output == *"make install"* ]] || false
	[ ! -e "$HOME/.local/bin/shtl" ]
}

@test "install says there is no build for another OS" {
	install_on FreeBSD amd64
	[ "$status" -eq 1 ]
	[[ $output == *"No shtl build for FreeBSD amd64"* ]] || false
}

@test "install stops when the checksum is wrong" {
	release_file linux-amd64-other
	mv "$RELEASE_DIR/shtl-linux-amd64-other.tar.gz" "$RELEASE_DIR/shtl-linux-amd64.tar.gz"
	install_on Linux x86_64
	[ "$status" -eq 1 ]
	[[ $output == *"checksum"* ]] || false
	[ ! -e "$HOME/.local/bin/shtl" ]
}

@test "install stops when a download fails" {
	rm "$RELEASE_DIR/checksums.txt"
	install_on Linux x86_64
	[ "$status" -eq 1 ]
	[ ! -e "$HOME/.local/bin/shtl" ]
}

@test "install replaces an older shtl" {
	mkdir -p "$HOME/.local/bin"
	echo old > "$HOME/.local/bin/shtl"
	install_on Linux x86_64
	[ "$status" -eq 0 ]
	[ "$("$HOME/.local/bin/shtl")" = "fake shtl linux-amd64" ]
}

@test "install says to run shtl setup" {
	install_on Linux x86_64
	[[ $output == *"Installed shtl in ~/.local/bin/shtl"* ]] || false
	[[ $output == *"shtl setup"* ]] || false
}

@test "install warns when ~/.local/bin is not on PATH" {
	install_on Linux x86_64
	[[ $output == *"~/.local/bin is not on your PATH"* ]] || false
	PATH="$HOME/.local/bin:$PATH" install_on Linux x86_64
	[[ $output != *"not on your PATH"* ]] || false
}

@test "install gives a setup command that runs when ~/.local/bin is not on PATH" {
	install_on Linux x86_64
	[[ $output == *"run: ~/.local/bin/shtl setup"* ]] || false
	PATH="$HOME/.local/bin:$PATH" install_on Linux x86_64
	[[ $output == *"run: shtl setup"* ]] || false
}
