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

## Verify Installation

Execute: `shtl`

You should be presented with the `usage` of `shtl`

```

shtl - Help

    -l | --list    Display available routes
    -h | --help    Display this information
    -a | --add     ROUTE_NAME [ROUTE] [-p|--persist] Add a route. Provide only the name unless you're not current in the desired route path
                   --persist keeps the route even if its directory doesn't exist (clean will skip it)
    -c | --clean   Interactively remove routes whose directories no longer exist
    -p | --persist ROUTE_NAME Toggle whether clean skips a route
    -d | --delete  ROUTE_NAME Delete a route via its route name
    -m | --modify  ROUTE_NAME ROUTE Modify a route via its route name
    -v | --version Prints current shtl version
         --path    ROUTE_NAME Print a route's path (e.g. cp file "$(shtl --path work)")
         init      Print the shell function. Add to your ~/.zshrc or ~/.bashrc: eval "$(shtl init)"

```

## Contribute

1. Clone this repository
2. Create a branch
3. Open a Pull Request with your branch

