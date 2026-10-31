// Command-line behavior that doesn't need routes: version, help, and
// unknown commands.

mod common;

use common::{Env, run};

fn with_args(args: &[&str]) -> (String, String, i32) {
    let env = Env::new();
    let mut cmd = env.shtl();
    cmd.args(args);
    run(cmd)
}

#[test]
fn version_prints_the_crate_version() {
    assert_eq!(
        with_args(&["version"]),
        (format!("{}\n", env!("CARGO_PKG_VERSION")), String::new(), 0)
    );
}

#[test]
fn help_prints_usage() {
    let (out, _, code) = with_args(&["help"]);
    assert_eq!(code, 0);
    assert!(out.contains("Usage: shtl ROUTE_NAME [SUBDIR]"), "{out}");
    assert!(out.contains("version"), "{out}");
}

#[test]
fn no_arguments_prints_the_same_usage_as_help() {
    let (out, _, code) = with_args(&[]);
    assert_eq!(code, 0);
    assert!(out.contains("Usage:"), "{out}");
    assert_eq!(out, with_args(&["help"]).0);
}

#[test]
fn unknown_command_is_an_error_with_usage() {
    let (out, err, code) = with_args(&["nope"]);
    assert_eq!(code, 1);
    assert_eq!(
        err,
        "shtl [ERROR] \"nope\" is not a shtl command or route\n"
    );
    assert!(out.contains("Usage:"), "{out}");
}
