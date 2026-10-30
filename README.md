# SHTL

## Install

> The following assumes you are in the project's root directory.

**Execute:** `make install`

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

```

## Contribute

1. Clone this repository
2. Create a branch
3. Open a Pull Request with your branch

