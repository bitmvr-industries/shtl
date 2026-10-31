// clean without a terminal. The interactive screen is tested with expect
// in test/clean.bats.

mod common;

use common::{Env, host, run};

fn clean(env: &Env) -> (String, String, i32) {
    let mut cmd = env.shtl();
    cmd.arg("clean");
    run(cmd)
}

#[test]
fn clean_with_no_routes_says_how_to_add_one() {
    let env = Env::new();
    env.write_routes(
        "version = 2\n[[route]]\nname = \"far\"\npath = \"/gone\"\nhosts = [\"not-this-host\"]\n",
    );
    assert_eq!(
        clean(&env),
        (
            String::new(),
            "shtl [INFO]  No routes to clean. Add one with: shtl add NAME [PATH]\n".into(),
            0
        )
    );
}

#[test]
fn clean_never_offers_persistent_or_no_host_routes() {
    let env = Env::new();
    let text = format!(
        "version = 2\n\
         [[route]]\nname = \"here\"\npath = \"{}\"\nhosts = [\"{h}\"]\n\
         [[route]]\nname = \"nas\"\npath = \"/gone/nas\"\npersist = true\nhosts = [\"{h}\"]\n\
         [[route]]\nname = \"everywhere\"\npath = \"/gone/everywhere\"\n\
         [[route]]\nname = \"far\"\npath = \"/gone/far\"\nhosts = [\"not-this-host\"]\n",
        env.root.display(),
        h = host()
    );
    env.write_routes(&text);
    assert_eq!(
        clean(&env),
        (
            String::new(),
            "shtl [INFO]  All routes point to existing directories\n".into(),
            0
        )
    );
}

#[test]
fn clean_needs_a_terminal() {
    let env = Env::new();
    let text = format!(
        "version = 2\n[[route]]\nname = \"gone\"\npath = \"/gone\"\nhosts = [\"{}\"]\n",
        host()
    );
    env.write_routes(&text);
    let (_, err, code) = clean(&env);
    assert_eq!(
        (err.as_str(), code),
        ("shtl [ERROR] Clean needs an interactive terminal\n", 1)
    );
    assert_eq!(std::fs::read_to_string(env.routes_file()).unwrap(), text);
}
