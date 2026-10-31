mod common;

use std::os::unix::fs::PermissionsExt;

use common::{Env, host, run};

fn with_args(env: &Env, args: &[&str]) -> (String, String, i32) {
    let mut cmd = env.shtl();
    cmd.args(args);
    run(cmd)
}

fn file(env: &Env) -> String {
    std::fs::read_to_string(env.routes_file()).unwrap()
}

/// The text shtl writes for a new route on this host
fn new_route(name: &str, path: &str, persist: bool) -> String {
    let persist = if persist { "persist = true\n" } else { "" };
    format!(
        "\n[[route]]\nname = \"{name}\"\npath = \"{path}\"\n{persist}hosts = [\"{}\"]\n",
        host()
    )
}

const NAME_RULES: &str = "shtl [ERROR] Route names can't be empty, start with \"-\", contain spaces or control characters, or be a shtl command (add, update, remove, rm, list, ls, clean, persist, path, doctor, setup, unsetup, init, help, version)\n";

#[test]
fn add_writes_a_route_for_this_host() {
    let env = Env::new();
    let dir = env.dir("work");
    let (out, err, code) = with_args(&env, &["add", "work", dir.to_str().unwrap()]);
    assert_eq!((out.as_str(), err.as_str(), code), ("", "", 0));
    assert_eq!(
        file(&env),
        format!(
            "version = 2\n{}",
            new_route("work", dir.to_str().unwrap(), false)
        )
    );
}

#[test]
fn add_defaults_to_the_current_directory_as_the_shell_shows_it() {
    let mut env = Env::new();
    let dir = env.dir("here");
    env.cd(&dir);
    assert_eq!(with_args(&env, &["add", "here"]).2, 0);
    assert!(file(&env).contains(&format!("path = \"{}\"", dir.display())));
}

#[test]
fn add_stores_paths_in_home_with_a_tilde() {
    let env = Env::new();
    std::fs::create_dir_all(env.home.join("code")).unwrap();
    let typed = format!("{}/./code/", env.home.display());
    assert_eq!(with_args(&env, &["add", "code", &typed]).2, 0);
    assert_eq!(with_args(&env, &["add", "code2", "~/code"]).2, 0);
    let text = file(&env);
    assert!(
        text.contains("name = \"code\"\npath = \"~/code\""),
        "{text}"
    );
    assert!(
        text.contains("name = \"code2\"\npath = \"~/code\""),
        "{text}"
    );
}

#[test]
fn add_persist_allows_a_missing_directory() {
    let env = Env::new();
    let missing = env.root.join("later");
    let missing = missing.to_str().unwrap();
    assert_eq!(
        with_args(&env, &["add", "--persist", "later", missing]).2,
        0
    );
    assert_eq!(with_args(&env, &["add", "later2", missing, "-p"]).2, 0);
    let text = file(&env);
    assert!(text.contains(&new_route("later", missing, true)), "{text}");
    assert!(text.contains(&new_route("later2", missing, true)), "{text}");
}

#[test]
fn add_without_persist_needs_the_directory() {
    let env = Env::new();
    let missing = format!("{}/later", env.root.display());
    let (_, err, code) = with_args(&env, &["add", "later", &missing]);
    assert_eq!(code, 1);
    assert_eq!(
        err,
        format!(
            "shtl [ERROR] \"{missing}\" does not exist. Only a persistent route can point to a missing directory. To add a route for a directory that will exist later, use --persist\n"
        )
    );
    assert!(!env.routes_file().exists());
}

#[test]
fn add_refuses_a_file() {
    let env = Env::new();
    let f = env.root.join("f");
    std::fs::write(&f, "").unwrap();
    let (_, err, code) = with_args(&env, &["add", "--persist", "f", f.to_str().unwrap()]);
    assert_eq!(code, 1);
    assert_eq!(
        err,
        format!("shtl [ERROR] \"{}\" is not a directory\n", f.display())
    );
}

#[test]
fn add_refuses_a_relative_path() {
    let env = Env::new();
    let (_, err, code) = with_args(&env, &["add", "x", "rel"]);
    assert_eq!(code, 1);
    assert_eq!(
        err,
        "shtl [ERROR] \"rel\" is not an absolute path. Use a full path starting with \"/\", or leave PATH out to use the current directory\n"
    );
}

#[test]
fn add_needs_a_name() {
    let env = Env::new();
    let (_, err, code) = with_args(&env, &["add"]);
    assert_eq!(
        (err.as_str(), code),
        ("shtl [ERROR] Please provide a route name\n", 1)
    );
    let (_, err, code) = with_args(&env, &["add", "--persist"]);
    assert_eq!(
        (err.as_str(), code),
        ("shtl [ERROR] Please provide a route name\n", 1)
    );
}

#[test]
fn add_refuses_bad_names() {
    let env = Env::new();
    let dir = env.root.to_str().unwrap();
    for name in ["", "-x", "a b", "tab\tname", "list", "rm"] {
        let (_, err, code) = with_args(&env, &["add", name, dir]);
        assert_eq!((err.as_str(), code), (NAME_RULES, 1), "name {name:?}");
    }
    assert!(!env.routes_file().exists());
}

#[test]
fn add_allows_characters_the_old_format_reserved() {
    let env = Env::new();
    let dir = env.root.to_str().unwrap();
    assert_eq!(with_args(&env, &["add", "a:b[c]#d", dir]).2, 0);
    assert_eq!(with_args(&env, &["path", "a:b[c]#d"]).0, format!("{dir}\n"));
}

#[test]
fn add_refuses_a_name_that_already_works_here() {
    let env = Env::new();
    let text = format!(
        "version = 2\n[[route]]\nname = \"mine\"\npath = \"/srv/m\"\nhosts = [\"{}\"]\n[[route]]\nname = \"all\"\npath = \"/srv/a\"\n",
        host()
    );
    env.write_routes(&text);
    let dir = env.root.to_str().unwrap();
    for name in ["mine", "all"] {
        let (_, err, code) = with_args(&env, &["add", name, dir]);
        assert_eq!(code, 1);
        assert_eq!(
            err,
            format!(
                "shtl [ERROR] Route \"{name}\" already exists. To change its path, run: shtl update {name} PATH\n"
            )
        );
    }
    assert_eq!(file(&env), text);
}

#[test]
fn add_joins_another_hosts_route_with_the_same_path() {
    let env = Env::new();
    std::fs::create_dir_all(env.home.join("work")).unwrap();
    env.write_routes("version = 2\n\n# Shared\n[[route]]\nname = \"work\"\npath = \"~/work\"\nhosts = [\"not-this-host\"]\n");
    assert_eq!(with_args(&env, &["add", "work", "~/work"]).2, 0);
    assert_eq!(
        file(&env),
        format!(
            "version = 2\n\n# Shared\n[[route]]\nname = \"work\"\npath = \"~/work\"\nhosts = [\"not-this-host\", \"{}\"]\n",
            host()
        )
    );
}

#[test]
fn add_makes_its_own_route_when_another_host_has_a_different_path() {
    let env = Env::new();
    let dir = env.dir("downloads");
    let theirs = "version = 2\n[[route]]\nname = \"downloads\"\npath = \"/var/tmp/downloads\"\nhosts = [\"not-this-host\"]\n";
    env.write_routes(theirs);
    assert_eq!(
        with_args(&env, &["add", "downloads", dir.to_str().unwrap()]).2,
        0
    );
    assert_eq!(
        file(&env),
        format!(
            "{theirs}{}",
            new_route("downloads", dir.to_str().unwrap(), false)
        )
    );
}

#[test]
fn add_keeps_comments_blank_lines_and_order() {
    let env = Env::new();
    let dir = env.dir("b");
    let before = "version = 2   # format\n\n# Machines\n\n[[route]]\nname = \"z\"   # last name, first place\npath = \"/srv/z\"\n\n\n[[route]]\nname = \"a\"\npath = \"/srv/a\"\n";
    env.write_routes(before);
    assert_eq!(with_args(&env, &["add", "b", dir.to_str().unwrap()]).2, 0);
    assert_eq!(
        file(&env),
        format!("{before}{}", new_route("b", dir.to_str().unwrap(), false))
    );
}

#[test]
fn add_writes_through_a_symlinked_routes_file() {
    let env = Env::new();
    let real = env.root.join("dotfiles-routes.toml");
    std::fs::write(&real, "version = 2\n").unwrap();
    std::fs::create_dir_all(env.config.join("shtl")).unwrap();
    std::os::unix::fs::symlink(&real, env.routes_file()).unwrap();
    assert_eq!(
        with_args(&env, &["add", "r", env.root.to_str().unwrap()]).2,
        0
    );
    let meta = std::fs::symlink_metadata(env.routes_file()).unwrap();
    assert!(meta.file_type().is_symlink());
    assert!(
        std::fs::read_to_string(&real)
            .unwrap()
            .contains("name = \"r\"")
    );
}

#[test]
fn add_keeps_the_routes_files_mode() {
    let env = Env::new();
    env.write_routes("version = 2\n");
    let perms = std::fs::Permissions::from_mode(0o600);
    std::fs::set_permissions(env.routes_file(), perms).unwrap();
    assert_eq!(
        with_args(&env, &["add", "r", env.root.to_str().unwrap()]).2,
        0
    );
    let mode = std::fs::metadata(env.routes_file())
        .unwrap()
        .permissions()
        .mode();
    assert_eq!(mode & 0o777, 0o600);
}

#[test]
fn add_warns_about_this_hosts_routes_to_the_same_directory() {
    let env = Env::new();
    let dir = env.dir("d");
    let d = dir.to_str().unwrap();
    env.write_routes(&format!(
        "version = 2\n\
         [[route]]\nname = \"w1\"\npath = \"{d}\"\n\
         [[route]]\nname = \"far\"\npath = \"{d}\"\nhosts = [\"not-this-host\"]\n"
    ));
    let (_, err, code) = with_args(&env, &["add", "w2", d]);
    assert_eq!(code, 0);
    assert_eq!(
        err,
        format!("shtl [WARN]  Route \"w1\" also points to {d}\n")
    );
}

#[test]
fn add_with_a_bad_routes_file_changes_nothing() {
    let env = Env::new();
    env.write_routes("version = 1\n");
    let (_, err, code) = with_args(&env, &["add", "r", env.root.to_str().unwrap()]);
    assert_eq!(code, 1);
    assert!(err.contains("version = 2"), "{err}");
    assert_eq!(file(&env), "version = 1\n");
}
