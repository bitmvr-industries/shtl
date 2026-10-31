# shtl

[![CI](https://github.com/bitmvr-industries/shtl/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/bitmvr-industries/shtl/actions/workflows/ci.yml)

`shtl` saves directories as routes with short names. Then you go to a directory with its route name. `shtl` operates in zsh and bash, on macOS and Linux.

```sh
shtl add work        # save the current directory as "work"
shtl work            # go to it
shtl work code/api   # go to a folder in it (Tab completes it)
```

## Install

```sh
brew install bitmvr-industries/tap/shtl
shtl setup
```

Then open a new terminal.

| Method | Install | Upgrade | Remove |
|---|---|---|---|
| Homebrew | `brew install bitmvr-industries/tap/shtl` | `brew upgrade shtl` | `shtl unsetup`, then `brew uninstall shtl` |
| Release file | The `curl` command below | The `curl` command again | `shtl unsetup`, then delete `~/.local/bin/shtl` |
| Source | `make install` | `git pull`, then `make install` | `make uninstall` |

Release file (`~/.local/bin` must be in your `PATH`):

```sh
mkdir -p ~/.local/bin
curl -fsSL -o ~/.local/bin/shtl https://github.com/bitmvr-industries/shtl/releases/latest/download/shtl
chmod +x ~/.local/bin/shtl
```

`make install` installs `shtl` in `~/.local/bin` and does `shtl setup`. To use a different directory, set `PREFIX`, for example `sudo make install PREFIX=/usr/local`.

## Shell Integration

A script cannot change the directory of your shell. Thus, `shtl` has a shell function that does the `cd` command. The shell function also gives tab completion.

`shtl setup` adds the shell function to your rc file. It shows the changes and asks before it changes the file. `shtl unsetup` removes it.

| Shell | RC file |
|---|---|
| zsh | `$ZDOTDIR/.zshrc` or `~/.zshrc` |
| bash on Linux | `~/.bashrc` |
| bash on macOS | The first of `~/.bash_profile`, `~/.bash_login`, `~/.profile`. If that file reads `~/.bashrc`, then `~/.bashrc`. |

To add the shell function manually, add these lines to the end of your rc file. For zsh, add them after `compinit`.

```sh
# shtl: https://github.com/bitmvr-industries/shtl
if command -v shtl >/dev/null; then eval "$(shtl init)"; fi
```

## Commands

| Command | Description |
|---|---|
| `shtl NAME [SUBDIR]` | Go to a route, or to a folder in it. |
| `shtl add NAME [PATH] [--persist]` | Add a route. `PATH` is absolute. The default is the current directory. |
| `shtl update NAME [PATH]` | Change the path of a route. |
| `shtl remove NAME`, `shtl rm NAME` | Remove a route. |
| `shtl list`, `shtl ls` | Show the routes. A `*` shows the route that you are in. |
| `shtl clean` | Remove routes to directories that are not on the computer. |
| `shtl persist NAME` | Add or remove the `persist` flag. |
| `shtl path NAME [SUBDIR]` | Show the path, for example `cp file "$(shtl path work)"`. |
| `shtl doctor` | Find problems in the routes file. |
| `shtl setup`, `shtl unsetup` | Add or remove the shell function in your rc file. |
| `shtl init`, `shtl help`, `shtl version` | Show the shell function, the help text, or the version. |

## Routes File

The routes file is `~/.config/shtl/routes`, or `$XDG_CONFIG_HOME/shtl/routes` if you set `XDG_CONFIG_HOME`. It is plain text:

```
# shtl routes v1
nas[persist]:/Volumes/nas
work[]:~/work
```

- Each route is `NAME[FLAGS]:PATH`.
- `~` is the home directory of the computer.
- The `persist` flag lets a route point to a directory that is not on the computer. `shtl clean` does not remove it.
- A name must not contain `:`, `[` or `]`, start with `-` or `#`, or be a `shtl` command.
- `shtl` keeps comments, blank lines and the sequence of the routes.

If you change the file in a text editor, enter `shtl doctor` to find problems.

## Contribute

- Enter `make test` to do the tests. The tests use [bats](https://github.com/bats-core/bats-core) (`brew install bats-core`).
- Enter `make hooks` to do the lint and the tests before each push.
- CI does the tests on Linux only. On macOS, do the tests on your computer.
- [docs/pipeline.svg](docs/pipeline.svg) shows how `shtl` operates. To make it again from its source, enter `d2 docs/pipeline.d2 docs/pipeline.svg`.

## License

MIT. Refer to [LICENSE](LICENSE).
