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

#[test]
fn remove_deletes_a_route_only_this_host_has() {
    let env = Env::new();
    env.write_routes(&format!(
        "version = 2\n\n# Keep\n[[route]]\nname = \"a\"\npath = \"/a\"\n\n# Mine\n[[route]]\nname = \"work\"\npath = \"/w\"\nhosts = [\"{}\"]\n\n# End\n[[route]]\nname = \"z\"\npath = \"/z\"\n",
        host()
    ));
    let (out, err, code) = with_args(&env, &["remove", "work"]);
    assert_eq!((out.as_str(), err.as_str(), code), ("", "", 0));
    assert_eq!(
        file(&env),
        "version = 2\n\n# Keep\n[[route]]\nname = \"a\"\npath = \"/a\"\n\n# End\n[[route]]\nname = \"z\"\npath = \"/z\"\n"
    );
}

#[test]
fn rm_takes_this_host_out_of_a_shared_route() {
    let env = Env::new();
    env.write_routes(&format!(
        "version = 2\n[[route]]\nname = \"work\"\npath = \"/w\"  # shared\nhosts = [\"{}\", \"not-this-host\"]\n",
        host()
    ));
    assert_eq!(with_args(&env, &["rm", "work"]).2, 0);
    assert_eq!(
        file(&env),
        "version = 2\n[[route]]\nname = \"work\"\npath = \"/w\"  # shared\nhosts = [\"not-this-host\"]\n"
    );
}

#[test]
fn remove_of_a_route_with_no_hosts_says_it_is_gone_everywhere() {
    let env = Env::new();
    env.write_routes("version = 2\n[[route]]\nname = \"work\"\npath = \"/w\"\n");
    let (_, err, code) = with_args(&env, &["remove", "work"]);
    assert_eq!(code, 0);
    assert_eq!(
        err,
        "shtl [INFO]  Route \"work\" had no hosts, so it is removed on every machine\n"
    );
    assert_eq!(file(&env), "version = 2\n");
}

#[test]
fn remove_takes_the_host_route_that_wins_here_and_keeps_the_default() {
    let env = Env::new();
    env.write_routes(&format!(
        "version = 2\n[[route]]\nname = \"dl\"\npath = \"/default\"\n[[route]]\nname = \"dl\"\npath = \"/mine\"\nhosts = [\"{}\"]\n",
        host()
    ));
    assert_eq!(with_args(&env, &["remove", "dl"]).2, 0);
    assert_eq!(
        file(&env),
        "version = 2\n[[route]]\nname = \"dl\"\npath = \"/default\"\n"
    );
}

#[test]
fn remove_of_another_hosts_route_does_not_exist_here() {
    let env = Env::new();
    let text = "version = 2\n[[route]]\nname = \"work\"\npath = \"/w\"\nhosts = [\"not-this-host\"]\n[[route]]\nname = \"wide\"\npath = \"/x\"\n";
    env.write_routes(text);
    let (_, err, code) = with_args(&env, &["remove", "w"]);
    assert_eq!(code, 1);
    assert_eq!(
        err,
        "shtl [ERROR] Could not remove route \"w\". The route does not exist\nshtl [INFO]  Did you mean: wide\n"
    );
    let (_, err, code) = with_args(&env, &["remove", "work"]);
    assert_eq!(code, 1);
    assert_eq!(
        err,
        "shtl [ERROR] Could not remove route \"work\". The route does not exist\n"
    );
    assert_eq!(file(&env), text);
}

#[test]
fn remove_needs_a_name() {
    let env = Env::new();
    let (_, err, code) = with_args(&env, &["remove"]);
    assert_eq!(
        (err.as_str(), code),
        ("shtl [ERROR] Please provide a route name\n", 1)
    );
}
