mod common;

use common::{Env, host, run};

fn with_args(env: &Env, args: &[&str]) -> (String, String, i32) {
    let mut cmd = env.shtl();
    cmd.args(args);
    run(cmd)
}

fn file(env: &Env) -> String {
    std::fs::read_to_string(env.routes_file()).unwrap()
}

/// An env with directories root/old and root/new
fn env() -> (Env, String, String) {
    let env = Env::new();
    let old = env.dir("old").display().to_string();
    let new = env.dir("new").display().to_string();
    (env, old, new)
}

fn now_points(name: &str, path: &str) -> String {
    format!("shtl [INFO]  Route \"{name}\" now points to {path}\n")
}

#[test]
fn update_changes_a_route_only_this_host_has_in_place() {
    let (env, old, new) = env();
    let h = host();
    env.write_routes(&format!(
        "version = 2\n\n# Work\n[[route]]\nname = \"work\"\npath = \"{old}\"  # moved?\nhosts = [\"{h}\"]\n"
    ));
    let (out, err, code) = with_args(&env, &["update", "work", &new]);
    assert_eq!((out.as_str(), err, code), ("", now_points("work", &new), 0));
    assert_eq!(
        file(&env),
        format!(
            "version = 2\n\n# Work\n[[route]]\nname = \"work\"\npath = \"{new}\"  # moved?\nhosts = [\"{h}\"]\n"
        )
    );
}

#[test]
fn update_splits_this_host_off_a_shared_route() {
    let (env, old, new) = env();
    let h = host();
    env.write_routes(&format!(
        "version = 2\n\n[[route]]\nname = \"work\"\npath = \"{old}\"\nhosts = [\"{h}\", \"not-this-host\"]\n\n[[route]]\nname = \"z\"\npath = \"/z\"\n"
    ));
    assert_eq!(with_args(&env, &["update", "work", &new]).2, 0);
    assert_eq!(
        file(&env),
        format!(
            "version = 2\n\n[[route]]\nname = \"work\"\npath = \"{old}\"\nhosts = [\"not-this-host\"]\n\n[[route]]\nname = \"work\"\npath = \"{new}\"\nhosts = [\"{h}\"]\n\n[[route]]\nname = \"z\"\npath = \"/z\"\n"
        )
    );
}

#[test]
fn update_of_a_route_with_no_hosts_overrides_it_on_this_host() {
    let (env, old, new) = env();
    let h = host();
    env.write_routes(&format!(
        "version = 2\n[[route]]\nname = \"work\"\npath = \"{old}\"\n"
    ));
    assert_eq!(with_args(&env, &["update", "work", &new]).2, 0);
    assert_eq!(
        file(&env),
        format!(
            "version = 2\n[[route]]\nname = \"work\"\npath = \"{old}\"\n\n[[route]]\nname = \"work\"\npath = \"{new}\"\nhosts = [\"{h}\"]\n"
        )
    );
    assert_eq!(with_args(&env, &["path", "work"]).0, format!("{new}\n"));
}

#[test]
fn update_joins_another_hosts_route_to_the_new_path() {
    let (env, old, new) = env();
    let h = host();
    env.write_routes(&format!(
        "version = 2\n\n[[route]]\nname = \"work\"\npath = \"{old}\"\nhosts = [\"{h}\"]\n\n[[route]]\nname = \"work\"\npath = \"{new}\"\nhosts = [\"not-this-host\"]\n"
    ));
    assert_eq!(with_args(&env, &["update", "work", &new]).2, 0);
    assert_eq!(
        file(&env),
        format!(
            "version = 2\n\n[[route]]\nname = \"work\"\npath = \"{new}\"\nhosts = [\"not-this-host\", \"{h}\"]\n"
        )
    );
}

#[test]
fn update_defaults_to_the_current_directory() {
    let (mut env, old, new) = env();
    env.write_routes(&format!(
        "version = 2\n[[route]]\nname = \"work\"\npath = \"{old}\"\nhosts = [\"{}\"]\n",
        host()
    ));
    env.cd(&env.root.join("new"));
    assert_eq!(with_args(&env, &["update", "work"]).2, 0);
    assert!(file(&env).contains(&format!("path = \"{new}\"")));
}

#[test]
fn update_stores_home_paths_with_a_tilde() {
    let (env, old, _) = env();
    std::fs::create_dir_all(env.home.join("w")).unwrap();
    env.write_routes(&format!(
        "version = 2\n[[route]]\nname = \"work\"\npath = \"{old}\"\nhosts = [\"{}\"]\n",
        host()
    ));
    let (_, err, code) = with_args(&env, &["update", "work", "~/w"]);
    assert_eq!(code, 0);
    assert_eq!(
        err,
        now_points("work", &format!("{}/w", env.home.display()))
    );
    assert!(file(&env).contains("path = \"~/w\""));
}

#[test]
fn update_needs_the_directory_unless_the_route_is_persistent() {
    let (env, old, _) = env();
    let missing = format!("{}/missing", env.root.display());
    let text = format!(
        "version = 2\n[[route]]\nname = \"work\"\npath = \"{old}\"\nhosts = [\"{}\"]\n[[route]]\nname = \"nas\"\npath = \"{old}\"\npersist = true\n",
        host()
    );
    env.write_routes(&text);
    let (_, err, code) = with_args(&env, &["update", "work", &missing]);
    assert_eq!(code, 1);
    assert_eq!(
        err,
        format!(
            "shtl [ERROR] \"{missing}\" does not exist. Only a persistent route can point to a missing directory. To make this route persistent, run: shtl persist work. Then run this update again\n"
        )
    );
    assert_eq!(file(&env), text);

    assert_eq!(with_args(&env, &["update", "nas", &missing]).2, 0);
    assert!(file(&env).contains(&format!(
        "name = \"nas\"\npath = \"{missing}\"\npersist = true\nhosts = [\"{}\"]\n",
        host()
    )));
}

#[test]
fn update_of_an_unknown_route_suggests_names() {
    let (env, old, new) = env();
    let text = format!(
        "version = 2\n[[route]]\nname = \"work\"\npath = \"{old}\"\n[[route]]\nname = \"wide\"\npath = \"{old}\"\nhosts = [\"not-this-host\"]\n"
    );
    env.write_routes(&text);
    let (_, err, code) = with_args(&env, &["update", "wi", &new]);
    assert_eq!(code, 1);
    assert_eq!(
        err,
        "shtl [ERROR] Could not update route \"wi\". The route does not exist\n"
    );
    let (_, err, _) = with_args(&env, &["update", "w", &new]);
    assert_eq!(
        err,
        "shtl [ERROR] Could not update route \"w\". The route does not exist\nshtl [INFO]  Did you mean: work\n"
    );
    assert_eq!(file(&env), text);
}

#[test]
fn update_needs_a_name() {
    let (env, _, _) = env();
    let (_, err, code) = with_args(&env, &["update"]);
    assert_eq!(
        (err.as_str(), code),
        ("shtl [ERROR] Please provide a route name\n", 1)
    );
}

#[test]
fn update_warns_about_this_hosts_routes_to_the_same_directory() {
    let (env, old, new) = env();
    env.write_routes(&format!(
        "version = 2\n[[route]]\nname = \"work\"\npath = \"{old}\"\n[[route]]\nname = \"other\"\npath = \"{new}\"\n"
    ));
    let (_, err, code) = with_args(&env, &["update", "work", &new]);
    assert_eq!(code, 0);
    assert_eq!(
        err,
        format!(
            "shtl [WARN]  Route \"other\" also points to {new}\n{}",
            now_points("work", &new)
        )
    );
}

#[test]
fn update_to_the_same_path_leaves_the_file_alone() {
    let (env, old, _) = env();
    let text = format!(
        "version = 2\n[[route]]\nname = \"work\"\npath = \"{old}\"\nhosts = [\"{}\", \"not-this-host\"]\n",
        host()
    );
    env.write_routes(&text);
    let (_, err, code) = with_args(&env, &["update", "work", &old]);
    assert_eq!((err, code), (now_points("work", &old), 0));
    assert_eq!(file(&env), text);
}
