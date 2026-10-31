// Command-line behavior that doesn't need a routes file: version, help,
// and unknown commands.

use assert_cmd::Command;

fn shtl() -> Command {
    Command::cargo_bin("shtl").unwrap()
}

fn stdout_of(cmd: &mut Command) -> String {
    String::from_utf8(cmd.output().unwrap().stdout).unwrap()
}

#[test]
fn version_prints_the_crate_version() {
    shtl()
        .arg("version")
        .assert()
        .success()
        .stdout("2.0.0-dev\n");
}

#[test]
fn help_prints_usage() {
    let out = stdout_of(shtl().arg("help"));
    assert!(out.contains("Usage: shtl ROUTE_NAME [SUBDIR]"), "{out}");
    assert!(out.contains("version"), "{out}");
}

#[test]
fn no_arguments_prints_the_same_usage_as_help() {
    shtl().assert().success();
    let out = stdout_of(&mut shtl());
    assert!(out.contains("Usage:"), "{out}");
    assert_eq!(out, stdout_of(shtl().arg("help")));
}

#[test]
fn unknown_command_is_an_error_with_usage() {
    let output = shtl().arg("nope").output().unwrap();
    assert_eq!(output.status.code(), Some(1));
    assert_eq!(
        String::from_utf8(output.stderr).unwrap(),
        "shtl [ERROR] \"nope\" is not a shtl command or route\n"
    );
    assert!(String::from_utf8(output.stdout).unwrap().contains("Usage:"));
}
