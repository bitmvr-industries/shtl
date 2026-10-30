# SHTL

[![CI](https://github.com/bitmvr/shtl/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/bitmvr/shtl/actions/workflows/ci.yml)

## Install

> The following assumes you are in the project's root directory.

**Execute:** `make install`

This installs `shtl` to `~/.local/bin` with no `sudo`. Make sure that
directory is on your `PATH` (the install warns you if it isn't). To install
somewhere else, set `PREFIX`, e.g. `sudo make install PREFIX=/usr/local`.

To remove it: `make uninstall` (with the same `PREFIX`, if you set one).

## Shell Integration

A script can't change your shell's directory, so `shtl` ships a small shell
function that does the `cd` for it (plus tab completion of route names).

`make install` offers to append it to the end of your rc file (`~/.zshrc`,
or `~/.bash_profile` on macOS / `~/.bashrc` elsewhere). Nothing is changed
unless you answer `y`, and `make uninstall` offers to remove it again. To
add it yourself instead:

```sh
# shtl: https://github.com/bitmvr/shtl
if command -v shtl >/dev/null; then eval "$(shtl init)"; fi
```

In zsh, put it after `compinit` so tab completion is registered. Then
open a new terminal (or `source` the file) and jump with `shtl ROUTE_NAME`.

```sh
shtl add work              # save the current directory as "work"
shtl add nas /Volumes/nas --persist
shtl work                  # jump there
shtl ls                    # list routes
shtl clean                 # remove routes whose directories are gone
```

## Verify Installation

Execute: `shtl help`

You should be presented with the `usage` of `shtl`

```

shtl - Help

  Usage: shtl ROUTE_NAME
         shtl COMMAND [ARGS]

    ROUTE_NAME                      Jump to a route (needs the shell function, see init)
    add NAME [PATH] [-p|--persist]  Add a route. PATH must be absolute and defaults to the current directory
                                    --persist keeps the route even if its directory doesn't exist (clean skips it)
    update NAME [PATH]              Point a route at a new absolute path. PATH defaults to the current directory
    remove | rm NAME                Remove a route
    list | ls                       List routes
    clean                           Interactively remove routes whose directories no longer exist
    persist NAME                    Toggle whether clean skips a route
    path NAME                       Print a route's path (e.g. cp file "$(shtl path work)")
    init                            Print the shell function. Add to your ~/.zshrc or ~/.bashrc: eval "$(shtl init)"
    help                            Display this information
    version                         Print the shtl version

```

## Routes File

Routes live in `~/.config/shtl/routes` (or `$XDG_CONFIG_HOME/shtl/routes`),
one per line as `NAME[FLAGS]:PATH`. It's plain text, safe to edit by hand:

```
# shtl routes v2
nas[persist]:/Volumes/nas
work[]:/Users/me/work
```

`FLAGS` is a comma-separated list; `persist` is the only flag today. The
path comes last, so it can contain anything, colons included. Route names
can't contain `:`, `[` or `]`, or start with `-` or `#`.

Routes files from shtl 0.4.0 and earlier (`NAME:PATH[:persist]`) are
converted automatically the first time a newer shtl runs, and the original
is kept as `routes.v1.bak`.

## Contribute

1. Clone this repository
2. Create a branch
3. Run the tests: `make test` (needs [bats](https://github.com/bats-core/bats-core): `brew install bats-core`)
4. Open a Pull Request with your branch

Tests live in `test/` and run the built `shtl` against a temporary config
directory, so they never touch your real routes.

