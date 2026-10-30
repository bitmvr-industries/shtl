# SHTL

## Install

> The following assumes you are in the project's root directory.

**Execute:** `make install`

## Shell Integration

A script can't change your shell's directory, so `shtl` ships a small shell
function that does the `cd` for it (plus tab completion of route names).
Add this line to your `~/.zshrc` or `~/.bashrc`:

```sh
eval "$(shtl init)"
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
    add NAME [PATH] [-p|--persist]  Add a route. PATH defaults to the current directory
                                    --persist keeps the route even if its directory doesn't exist (clean skips it)
    remove | rm NAME                Remove a route
    list | ls                       List routes
    clean                           Interactively remove routes whose directories no longer exist
    persist NAME                    Toggle whether clean skips a route
    path NAME                       Print a route's path (e.g. cp file "$(shtl path work)")
    init                            Print the shell function. Add to your ~/.zshrc or ~/.bashrc: eval "$(shtl init)"
    help                            Display this information
    version                         Print the shtl version

```

## Contribute

1. Clone this repository
2. Create a branch
3. Open a Pull Request with your branch

