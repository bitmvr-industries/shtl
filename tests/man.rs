// The manual page, man/shtl.1, stays in step with the crate.

use shtl::commands::COMMANDS;

const PAGE: &str = include_str!("../man/shtl.1");

#[test]
fn names_the_crate_version() {
    let version = format!("\"shtl {}\"", env!("CARGO_PKG_VERSION"));
    let header = PAGE.lines().find(|l| l.starts_with(".TH ")).unwrap();
    assert!(header.contains(&version), "{header}");
}

#[test]
fn describes_every_command() {
    for command in COMMANDS {
        assert!(
            PAGE.contains(&format!("\\fB{command}\\fR")),
            "man/shtl.1 has no entry for {command}"
        );
    }
}
