mod common;

use common::{Env, host, run};

fn with_args(env: &Env, args: &[&str]) -> (String, String, i32) {
    let mut cmd = env.shtl();
    cmd.args(args);
    run(cmd)
}

#[test]
fn list_with_no_routes_file_says_how_to_add_one() {
    let env = Env::new();
    let (out, err, code) = with_args(&env, &["list"]);
    assert_eq!(code, 0);
    assert_eq!(out, "");
    assert_eq!(
        err,
        "shtl [INFO]  No routes yet. Add one with: shtl add NAME [PATH]\n"
    );
    assert!(!env.routes_file().exists());
}

#[test]
fn list_sorts_names_ignoring_case_and_pads_them() {
    let env = Env::new();
    env.write_routes(
        "version = 2\n\
         [[route]]\nname = \"b\"\npath = \"/srv/b\"\n\
         [[route]]\nname = \"Cee\"\npath = \"~/c\"\n\
         [[route]]\nname = \"a\"\npath = \"/srv/a\"\npersist = true\n",
    );
    let (out, _, code) = with_args(&env, &["list"]);
    assert_eq!(code, 0);
    assert_eq!(out, "a    /srv/a  (persist)\nb    /srv/b\nCee  ~/c\n");
}

#[test]
fn ls_is_list() {
    let env = Env::new();
    env.write_routes("version = 2\n[[route]]\nname = \"a\"\npath = \"/srv/a\"\n");
    assert_eq!(with_args(&env, &["ls"]).0, "a  /srv/a\n");
}

#[test]
fn list_shows_only_this_hosts_routes() {
    let env = Env::new();
    env.write_routes(&format!(
        "version = 2\n\
         [[route]]\nname = \"downloads\"\npath = \"~/Downloads\"\n\
         [[route]]\nname = \"downloads\"\npath = \"/var/tmp/downloads\"\nhosts = [\"{}\"]\n\
         [[route]]\nname = \"elsewhere\"\npath = \"/srv/x\"\nhosts = [\"not-this-host\"]\n\
         [[route]]\nname = \"shared\"\npath = \"/srv/s\"\nhosts = [\"not-this-host\", \"{}\"]\n",
        host(),
        host().to_uppercase()
    ));
    let (out, _, _) = with_args(&env, &["list"]);
    assert_eq!(out, "downloads  /var/tmp/downloads\nshared     /srv/s\n");
}

#[test]
fn list_marks_the_closest_route_that_contains_the_current_directory() {
    let mut env = Env::new();
    let root = env.root.display().to_string();
    let inner = env.dir("y/z");
    env.write_routes(&format!(
        "version = 2\n\
         [[route]]\nname = \"outer\"\npath = \"{root}\"\n\
         [[route]]\nname = \"inner\"\npath = \"{root}/y\"\n\
         [[route]]\nname = \"twin\"\npath = \"{root}/y/\"\n\
         [[route]]\nname = \"other\"\npath = \"/srv/o\"\n"
    ));
    env.cd(&inner);
    let (out, _, _) = with_args(&env, &["list"]);
    assert_eq!(
        out,
        format!("* inner  {root}/y\n  other  /srv/o\n  outer  {root}\n* twin   {root}/y/\n")
    );
}

#[test]
fn list_marks_a_home_route() {
    let mut env = Env::new();
    env.write_routes("version = 2\n[[route]]\nname = \"h\"\npath = \"~\"\n[[route]]\nname = \"o\"\npath = \"/srv/o\"\n");
    let home = env.home.clone();
    env.cd(&home);
    assert_eq!(with_args(&env, &["list"]).0, "* h  ~\n  o  /srv/o\n");
}

#[test]
fn list_has_no_mark_column_outside_every_route() {
    let env = Env::new();
    env.write_routes("version = 2\n[[route]]\nname = \"o\"\npath = \"/srv/o\"\n");
    assert_eq!(with_args(&env, &["list"]).0, "o  /srv/o\n");
}

#[test]
fn list_warns_about_a_route_named_like_a_command() {
    let env = Env::new();
    env.write_routes("version = 2\n[[route]]\nname = \"doctor\"\npath = \"/srv/d\"\n");
    let (out, err, code) = with_args(&env, &["list"]);
    assert_eq!(code, 0);
    assert_eq!(out, "doctor  /srv/d\n");
    assert_eq!(
        err,
        "shtl [WARN]  Route \"doctor\" has the same name as a shtl command, so shtl doctor runs the command. Use: cd \"$(shtl path doctor)\", or remove it and add it under a new name\n"
    );
}

#[test]
fn list_names_prints_this_hosts_names_sorted() {
    let env = Env::new();
    env.write_routes(
        "version = 2\n\
         [[route]]\nname = \"b\"\npath = \"/b\"\n\
         [[route]]\nname = \"A\"\npath = \"/a\"\n\
         [[route]]\nname = \"gone\"\npath = \"/g\"\nhosts = [\"not-this-host\"]\n",
    );
    let (out, err, code) = with_args(&env, &["list", "--names"]);
    assert_eq!((out.as_str(), err.as_str(), code), ("A\nb\n", "", 0));
}

#[test]
fn list_names_with_no_routes_prints_nothing() {
    let env = Env::new();
    assert_eq!(
        with_args(&env, &["list", "--names"]),
        (String::new(), String::new(), 0)
    );
}

#[test]
fn list_with_a_bad_routes_file_is_an_error() {
    let env = Env::new();
    env.write_routes("version = 1\n");
    let (out, err, code) = with_args(&env, &["list"]);
    assert_eq!(code, 1);
    assert_eq!(out, "");
    assert!(err.starts_with("shtl [ERROR] "), "{err}");
    assert!(err.contains("version = 2"), "{err}");
}
