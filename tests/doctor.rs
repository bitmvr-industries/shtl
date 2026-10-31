mod common;

use common::{Env, host, run};

fn doctor(env: &Env) -> (String, String, i32) {
    let mut cmd = env.shtl();
    cmd.arg("doctor");
    run(cmd)
}

#[test]
fn doctor_with_no_file_has_nothing_to_check() {
    let env = Env::new();
    assert_eq!(
        doctor(&env),
        (
            format!(
                "This host: {}\nThere is no routes file yet. Nothing to check\n",
                host()
            ),
            String::new(),
            0
        )
    );
    assert!(!env.routes_file().exists());
}

#[test]
fn doctor_on_a_good_file() {
    let env = Env::new();
    env.write_routes("version = 2\n[[route]]\nname = \"a\"\npath = \"/a\"\n");
    let file = env.routes_file().display().to_string();
    assert_eq!(
        doctor(&env),
        (
            format!("This host: {}\nNo problems found in {file}\n", host()),
            String::new(),
            0
        )
    );
}

#[test]
fn doctor_lists_the_problems_with_line_numbers() {
    let env = Env::new();
    env.write_routes("version = 2\n[[route]]\nname = \"list\"\npath = \"rel\"\n");
    let file = env.routes_file().display().to_string();
    let (out, err, code) = doctor(&env);
    assert_eq!((err.as_str(), code), ("", 1));
    assert_eq!(
        out,
        format!(
            "This host: {}\nProblems found in {file}:\n  Line 3: route name \"list\" is a shtl command, so shtl can't go to this route. Rename it\n  Line 4: path \"rel\" is not absolute. It must start with \"/\" or \"~/\"\n",
            host()
        )
    );
}

#[test]
fn doctor_reads_a_file_that_other_commands_reject() {
    let env = Env::new();
    env.write_routes("version = 1\n[[route]\n");
    let (out, _, code) = doctor(&env);
    assert_eq!(code, 1);
    assert!(out.contains("  Line 2, column 9: "), "{out}");
    env.write_routes("version = 1\n");
    let (out, _, code) = doctor(&env);
    assert_eq!(code, 1);
    assert!(out.contains("  Line 1: version must be 2"), "{out}");
}

#[test]
fn doctor_finds_two_routes_for_this_host() {
    let env = Env::new();
    let h = host();
    env.write_routes(&format!(
        "version = 2\n[[route]]\nname = \"a\"\npath = \"/a\"\nhosts = [\"{h}\"]\n[[route]]\nname = \"a\"\npath = \"/b\"\nhosts = [\"{h}\"]\n"
    ));
    let (out, _, code) = doctor(&env);
    assert_eq!(code, 1);
    assert!(
        out.contains(&format!(
            "  Line 6: route \"a\" is also on line 2 for host \"{h}\""
        )),
        "{out}"
    );
}
