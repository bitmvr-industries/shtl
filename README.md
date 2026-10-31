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

Release file, for macOS on Apple silicon and Linux on x86-64 or ARM64:

```sh
curl -fsSL https://raw.githubusercontent.com/bitmvr-industries/shtl/master/install.sh | sh
shtl setup
```

`install.sh` downloads the file for your computer from the latest release, examines its checksum and installs `shtl` in `~/.local/bin`. `~/.local/bin` must be in your `PATH`.

To install from the source, you must have [Rust](https://rustup.rs). `make install` builds `shtl` with `cargo`, installs it in `~/.local/bin` and does `shtl setup`. To use a different directory, set `PREFIX`, for example `sudo make install PREFIX=/usr/local`.

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
| `shtl add NAME [PATH] [--persist]` | Add a route for this host. `PATH` is absolute. The default is the current directory. |
| `shtl update NAME [PATH]` | Change the path of a route on this host. |
| `shtl remove NAME`, `shtl rm NAME` | Remove a route from this host. |
| `shtl list`, `shtl ls` | Show the routes of this host. A `*` shows the route that you are in. |
| `shtl clean` | Remove routes of this host that go to directories that are not on the computer. |
| `shtl persist NAME` | Set `persist` to `true` or `false` on this host. |
| `shtl path NAME [SUBDIR]` | Show the path, for example `cp file "$(shtl path work)"`. |
| `shtl doctor` | Find problems in the routes file. |
| `shtl setup`, `shtl unsetup` | Add or remove the shell function in your rc file. |
| `shtl init`, `shtl help`, `shtl version` | Show the shell function, the help text, or the version. |

## Routes File

The routes file is `~/.config/shtl/routes.toml`, or `$XDG_CONFIG_HOME/shtl/routes.toml` if you set `XDG_CONFIG_HOME`. It is a [TOML](https://toml.io) file:

```toml
version = 2

[[route]]
name = "downloads"
path = "~/Downloads"
hosts = ["mbp"]

[[route]]
name = "downloads"
path = "/var/tmp/downloads"
hosts = ["midgard"]

[[route]]
name = "nas"
path = "/Volumes/nas"
persist = true
```

- `version` is the version of the file format. It must be `2`.
- `path` is absolute. `~` is the home directory of the computer.
- `persist = true` lets a route go to a directory that is not on the computer. `shtl clean` does not remove the route.
- A name must not start with `-`, contain a space, or be a `shtl` command.
- `shtl` keeps comments, blank lines and the sequence of the routes.

If you change the file in a text editor, enter `shtl doctor` to find problems.

## Hosts

You can use one routes file on many computers, for example in a dotfiles repository. `hosts` is the list of the computers that use the route.

- A route with `hosts` operates only on these computers.
- A route without `hosts` operates on all computers. `shtl` does not make these routes. You add them in a text editor.
- If a route for this host and a route without `hosts` have the same name, `shtl` uses the route for this host.
- A new computer starts with no routes, because each route that `shtl` adds has `hosts`.

The host name is the `LocalHostName` on macOS and the host name before the first `.` on Linux. For example, `MBP` and `mbp` are the same host name. `shtl doctor` shows the host name.

A command changes the routes of this host only. The routes of other hosts do not change:

- `add` adds this host to `hosts`. If a route has the same name, path and `persist` value, `add` puts this host in that route.
- `update` and `persist` change the route if this host is the only host in it. If the route has other hosts, `shtl` removes this host from the route and adds a route for this host.
- `remove` removes this host from `hosts`. If no hosts stay, `remove` deletes the route. `remove` deletes a route without `hosts` on all computers.
- `clean` shows only the routes that have this host in `hosts`.

## Contribute

- Enter `make test` to do the tests. The tests use `cargo test` and [bats](https://github.com/bats-core/bats-core) (`brew install bats-core`). The bats tests also use `zsh` and `expect`.
- Enter `make lint` to do the lint: `cargo fmt`, `cargo clippy` and `shellcheck`.
- Enter `make hooks` to do the lint and the tests before each push.
- CI does the tests on Linux only. On macOS, do the tests on your computer.
- [docs/pipeline.svg](docs/pipeline.svg) shows how `shtl` operates. To make it again from its source, enter `d2 docs/pipeline.d2 docs/pipeline.svg`.

## License

MIT. Refer to [LICENSE](LICENSE).
