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

const NOW: &str = "shtl [INFO]  Route \"nas\" is now persistent. Clean will skip it\n";
const NO_LONGER: &str = "shtl [INFO]  Route \"nas\" is no longer persistent\n";

#[test]
fn persist_turns_on_for_a_route_only_this_host_has() {
    let env = Env::new();
    let h = host();
    env.write_routes(&format!(
        "version = 2\n# NAS\n[[route]]\nname = \"nas\"\npath = \"/srv/nas\"\nhosts = [\"{h}\"]\n"
    ));
    let (out, err, code) = with_args(&env, &["persist", "nas"]);
    assert_eq!((out.as_str(), err.as_str(), code), ("", NOW, 0));
    assert_eq!(
        file(&env),
        format!(
            "version = 2\n# NAS\n[[route]]\nname = \"nas\"\npath = \"/srv/nas\"\nhosts = [\"{h}\"]\npersist = true\n"
        )
    );
}

#[test]
fn persist_turns_off_and_removes_the_key() {
    let env = Env::new();
    let dir = env.root.display().to_string();
    let h = host();
    env.write_routes(&format!(
        "version = 2\n[[route]]\nname = \"nas\"\npath = \"{dir}\"\npersist = true\nhosts = [\"{h}\"]\n"
    ));
    let (_, err, code) = with_args(&env, &["persist", "nas"]);
    assert_eq!((err.as_str(), code), (NO_LONGER, 0));
    assert_eq!(
        file(&env),
        format!("version = 2\n[[route]]\nname = \"nas\"\npath = \"{dir}\"\nhosts = [\"{h}\"]\n")
    );
}

#[test]
fn persist_off_needs_the_directory() {
    let env = Env::new();
    std::fs::create_dir_all(env.home.join("x")).unwrap();
    let text = format!(
        "version = 2\n[[route]]\nname = \"nas\"\npath = \"~/gone\"\npersist = true\nhosts = [\"{}\"]\n",
        host()
    );
    env.write_routes(&text);
    let (_, err, code) = with_args(&env, &["persist", "nas"]);
    assert_eq!(code, 1);
    assert_eq!(
        err,
        format!(
            "shtl [ERROR] \"{}/gone\" does not exist. Only a persistent route can point to a missing directory. Point it at an existing directory with: shtl update nas PATH, or remove it\n",
            env.home.display()
        )
    );
    assert_eq!(file(&env), text);
}

#[test]
fn persist_splits_this_host_off_a_shared_route() {
    let env = Env::new();
    let h = host();
    env.write_routes(&format!(
        "version = 2\n[[route]]\nname = \"nas\"\npath = \"/srv/nas\"\nhosts = [\"not-this-host\", \"{h}\"]\n"
    ));
    assert_eq!(with_args(&env, &["persist", "nas"]).1, NOW);
    assert_eq!(
        file(&env),
        format!(
            "version = 2\n[[route]]\nname = \"nas\"\npath = \"/srv/nas\"\nhosts = [\"not-this-host\"]\n\n[[route]]\nname = \"nas\"\npath = \"/srv/nas\"\npersist = true\nhosts = [\"{h}\"]\n"
        )
    );
}

#[test]
fn persist_of_a_route_with_no_hosts_overrides_it_on_this_host() {
    let env = Env::new();
    let h = host();
    env.write_routes("version = 2\n[[route]]\nname = \"nas\"\npath = \"/srv/nas\"\n");
    assert_eq!(with_args(&env, &["persist", "nas"]).1, NOW);
    assert_eq!(
        file(&env),
        format!(
            "version = 2\n[[route]]\nname = \"nas\"\npath = \"/srv/nas\"\n\n[[route]]\nname = \"nas\"\npath = \"/srv/nas\"\npersist = true\nhosts = [\"{h}\"]\n"
        )
    );
    assert!(with_args(&env, &["list"]).0.contains("(persist)"));
}

#[test]
fn persist_joins_another_hosts_route_with_the_new_value() {
    let env = Env::new();
    let h = host();
    env.write_routes(&format!(
        "version = 2\n[[route]]\nname = \"nas\"\npath = \"/srv/nas\"\nhosts = [\"{h}\"]\n[[route]]\nname = \"nas\"\npath = \"/srv/nas\"\npersist = true\nhosts = [\"not-this-host\"]\n"
    ));
    assert_eq!(with_args(&env, &["persist", "nas"]).1, NOW);
    assert_eq!(
        file(&env),
        format!(
            "version = 2\n[[route]]\nname = \"nas\"\npath = \"/srv/nas\"\npersist = true\nhosts = [\"not-this-host\", \"{h}\"]\n"
        )
    );
}

#[test]
fn persist_of_an_unknown_route_is_an_error() {
    let env = Env::new();
    env.write_routes("version = 2\n[[route]]\nname = \"nas\"\npath = \"/srv/nas\"\nhosts = [\"not-this-host\"]\n");
    let (_, err, code) = with_args(&env, &["persist", "nas"]);
    assert_eq!(code, 1);
    assert_eq!(
        err,
        "shtl [ERROR] Could not persist route \"nas\". The route does not exist\n"
    );
}

#[test]
fn persist_needs_a_name() {
    let env = Env::new();
    let (_, err, code) = with_args(&env, &["persist"]);
    assert_eq!(
        (err.as_str(), code),
        ("shtl [ERROR] Please provide a route name\n", 1)
    );
}
