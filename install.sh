#!/bin/sh

# Installs the latest shtl release in ~/.local/bin and its manual page in
# ~/.local/share/man/man1:
#   curl -fsSL https://raw.githubusercontent.com/bitmvr-industries/shtl/master/install.sh | sh
# Picks the build for this OS and CPU and checks its checksum.

set -eu

RELEASE_URL="https://github.com/bitmvr-industries/shtl/releases/latest/download"
BIN_DIR="$HOME/.local/bin"
MAN_DIR="$HOME/.local/share/man/man1"

fail() {
	echo "shtl install: $1" >&2
	exit 1
}

os="$(uname -s)"
arch="$(uname -m)"
case "$os $arch" in
	"Darwin arm64") build="darwin-arm64" ;;
	"Linux x86_64" | "Linux amd64") build="linux-amd64" ;;
	"Linux aarch64" | "Linux arm64") build="linux-arm64" ;;
	*) fail "No shtl build for $os $arch. To build it from the source, clone https://github.com/bitmvr-industries/shtl and run: make install" ;;
esac
file="shtl-$build.tar.gz"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL -o "$tmp/$file" "$RELEASE_URL/$file" || fail "Could not download $RELEASE_URL/$file"
curl -fsSL -o "$tmp/checksums.txt" "$RELEASE_URL/checksums.txt" || fail "Could not download $RELEASE_URL/checksums.txt"

grep "  $file\$" "$tmp/checksums.txt" > "$tmp/check.txt" || fail "checksums.txt has no checksum for $file"
if command -v sha256sum > /dev/null; then
	(cd "$tmp" && sha256sum -c check.txt > /dev/null 2>&1) || fail "The checksum of $file is wrong. Nothing was installed"
else
	(cd "$tmp" && shasum -a 256 -c check.txt > /dev/null 2>&1) || fail "The checksum of $file is wrong. Nothing was installed"
fi

tar -xzf "$tmp/$file" -C "$tmp" shtl shtl.1
mkdir -p "$BIN_DIR" "$MAN_DIR"
# Replace the file, so a running shtl keeps its copy
mv -f "$tmp/shtl" "$BIN_DIR/shtl"
mv -f "$tmp/shtl.1" "$MAN_DIR/shtl.1"

echo "Installed shtl in ~/.local/bin/shtl. For its manual, run: man shtl"
# shellcheck disable=SC2088 # the messages show ~ on purpose
case ":$PATH:" in
	*":$BIN_DIR:"*)
		echo "To add the shell function to your rc file, run: shtl setup"
		;;
	*)
		echo "~/.local/bin is not on your PATH. Add it in your shell's rc file."
		echo "To add the shell function to your rc file, run: ~/.local/bin/shtl setup"
		;;
esac
