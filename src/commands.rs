//! shtl's commands. A route can't use one of these names, and the shell
//! function from `shtl init` passes them straight through to shtl.

pub const COMMANDS: [&str; 15] = [
    "add", "update", "remove", "rm", "list", "ls", "clean", "persist", "path", "doctor", "setup",
    "unsetup", "init", "help", "version",
];

pub fn is_command(name: &str) -> bool {
    COMMANDS.contains(&name)
}
