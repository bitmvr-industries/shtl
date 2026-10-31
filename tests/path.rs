mod common;

use common::{Env, host, run};

fn with_args(env: &Env, args: &[&str]) -> (String, String, i32) {
    let mut cmd = env.shtl();
    cmd.args(args);
    run(cmd)
}

/// An env with route "work" → root/work (which has a "sub" folder) and
/// route "World" → ~/world, both existing
fn env_with_routes() -> Env {
    let env = Env::new();
    env.dir("work/sub");
    std::fs::create_dir_all(env.home.join("world")).unwrap();
    env.write_routes(&format!(
        "version = 2\n\
         [[route]]\nname = \"work\"\npath = \"{}/work\"\n\
         [[route]]\nname = \"World\"\npath = \"~/world\"\nhosts = [\"{}\"]\n\
         [[route]]\nname = \"wide\"\npath = \"/srv\"\nhosts = [\"not-this-host\"]\n\
         [[route]]\nname = \"gone\"\npath = \"/no/such/dir\"\npersist = true\n",
        env.root.display(),
        host()
    ));
    env
}

#[test]
fn path_prints_the_routes_directory() {
    let env = env_with_routes();
    let want = format!("{}/work\n", env.root.display());
    assert_eq!(with_args(&env, &["path", "work"]), (want, String::new(), 0));
}

#[test]
fn path_expands_a_home_route() {
    let env = env_with_routes();
    let want = format!("{}/world\n", env.home.display());
    assert_eq!(with_args(&env, &["path", "World"]).0, want);
}

#[test]
fn path_with_subdir_prints_the_folder_in_the_route() {
    let env = env_with_routes();
    let want = format!("{}/work/sub\n", env.root.display());
    assert_eq!(
        with_args(&env, &["path", "work", "./sub/"]),
        (want, String::new(), 0)
    );
}

#[test]
fn path_needs_a_route_name() {
    let env = env_with_routes();
    let (out, err, code) = with_args(&env, &["path"]);
    assert_eq!((out.as_str(), code), ("", 1));
    assert_eq!(err, "shtl [ERROR] Please provide a route name\n");
}

#[test]
fn path_of_an_unknown_route_suggests_names_that_start_the_same() {
    let env = env_with_routes();
    let (out, err, code) = with_args(&env, &["path", "w"]);
    assert_eq!((out.as_str(), code), ("", 1));
    assert_eq!(
        err,
        "shtl [ERROR] Route \"w\" does not exist\nshtl [INFO]  Did you mean: work, World\n"
    );
}

#[test]
fn path_of_another_hosts_route_does_not_exist_here() {
    let env = env_with_routes();
    let (_, err, code) = with_args(&env, &["path", "wide"]);
    assert_eq!(code, 1);
    assert!(
        err.starts_with("shtl [ERROR] Route \"wide\" does not exist\n"),
        "{err}"
    );
}

#[test]
fn path_of_a_route_to_a_missing_directory_is_an_error() {
    let env = env_with_routes();
    let (out, err, code) = with_args(&env, &["path", "gone"]);
    assert_eq!((out.as_str(), code), ("", 1));
    assert_eq!(
        err,
        "shtl [ERROR] Route \"gone\" points to /no/such/dir, which doesn't exist\n"
    );
}

#[test]
fn path_subdir_must_be_relative() {
    let env = env_with_routes();
    let (_, err, code) = with_args(&env, &["path", "work", "/sub"]);
    assert_eq!(code, 1);
    assert_eq!(
        err,
        "shtl [ERROR] \"/sub\" must be relative to the route. Leave out the leading \"/\"\n"
    );
}

#[test]
fn path_subdir_must_exist() {
    let env = env_with_routes();
    let (_, err, code) = with_args(&env, &["path", "work", "zz/.."]);
    assert_eq!(code, 0, "{err}");
    let (_, err, code) = with_args(&env, &["path", "work", "zz"]);
    assert_eq!(code, 1);
    assert_eq!(
        err,
        format!(
            "shtl [ERROR] \"{}/work/zz\" does not exist\n",
            env.root.display()
        )
    );
}

#[test]
fn a_route_name_as_the_command_prints_the_path_and_how_to_set_up_cd() {
    let env = env_with_routes();
    let (out, err, code) = with_args(&env, &["work", "sub"]);
    assert_eq!(code, 0);
    assert_eq!(out, format!("{}/work/sub\n", env.root.display()));
    assert_eq!(
        err,
        "shtl [WARN]  shtl can't change directory without its shell function. To set it up, run: shtl setup\n"
    );
}

#[test]
fn a_route_name_with_a_bad_subdir_fails_without_the_setup_warning() {
    let env = env_with_routes();
    let (out, err, code) = with_args(&env, &["work", "zz"]);
    assert_eq!((out.as_str(), code), ("", 1));
    assert!(!err.contains("setup"), "{err}");
}

#[test]
fn an_unknown_name_suggests_routes_instead_of_usage() {
    let env = env_with_routes();
    let (out, err, code) = with_args(&env, &["WO"]);
    assert_eq!((out.as_str(), code), ("", 1));
    assert_eq!(
        err,
        "shtl [ERROR] \"WO\" is not a shtl command or route\nshtl [INFO]  Did you mean: work, World\n"
    );
}

#[test]
fn an_unknown_name_with_no_suggestions_prints_usage() {
    let env = env_with_routes();
    let (out, err, code) = with_args(&env, &["zzz"]);
    assert_eq!(code, 1);
    assert_eq!(err, "shtl [ERROR] \"zzz\" is not a shtl command or route\n");
    assert!(out.contains("Usage:"), "{out}");
}

#[test]
fn a_route_name_with_a_bad_routes_file_is_an_error() {
    let env = Env::new();
    env.write_routes("version = 2\n[[route]]\nname = \"work\"\n");
    let (out, err, code) = with_args(&env, &["work"]);
    assert_eq!((out.as_str(), code), ("", 1));
    assert!(err.contains("line 2"), "{err}");
    assert!(!err.contains("is not a shtl command"), "{err}");
}
