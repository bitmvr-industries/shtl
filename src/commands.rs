//! shtl's commands. A route can't use one of these names, and the shell
//! function from `shtl init` passes them straight through to shtl.

pub const COMMANDS: [&str; 15] = [
    "add", "update", "remove", "rm", "list", "ls", "clean", "persist", "path", "doctor", "setup",
    "unsetup", "init", "help", "version",
];

pub fn is_command(name: &str) -> bool {
    COMMANDS.contains(&name)
}

/// Names are free text in TOML. They can't start with "-" (flags), have
/// white space (completion splits on it) or control characters, or be a
/// command.
pub fn valid_name(name: &str) -> bool {
    !name.is_empty()
        && !name.starts_with('-')
        && !name.chars().any(|c| c.is_whitespace() || c.is_control())
        && !is_command(name)
}
