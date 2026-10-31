//! Reads the command line and runs the command.

use std::process::ExitCode;

use crate::commands::{COMMANDS, is_command};
use crate::routes::{self, Route};
use crate::{host, log, paths};

const USAGE: &str = r#"
shtl - Help

  Usage: shtl ROUTE_NAME [SUBDIR]
         shtl COMMAND [ARGS]

    ROUTE_NAME [SUBDIR]             Jump to a route, or a folder under it (needs the shell function, see setup)
    add NAME [PATH] [-p|--persist]  Add a route. PATH must be absolute and defaults to the current directory
                                    --persist allows a directory that doesn't exist yet, and clean skips the route
    update NAME [PATH]              Point a route at a new absolute path. PATH defaults to the current directory
    remove | rm NAME                Remove a route
    list | ls                       List routes. * marks the route you are in
    clean                           Interactively remove routes whose directories no longer exist
    persist NAME                    Toggle whether clean skips a route
    path NAME [SUBDIR]              Print a route's path (e.g. cp file "$(shtl path work)")
    doctor                          Check the routes file for problems
    setup                           Add the shell function to your shell's rc file (asks first)
    unsetup                         Remove the shell function from your rc files (asks first)
    init                            Print the shell function. setup adds it to your rc file for you
    help                            Display this information
    version                         Print the shtl version

"#;

/// A failed command. Its message is already logged.
struct Failed;

type Outcome = Result<(), Failed>;

pub fn run(args: &[String]) -> ExitCode {
    let command = args.first().map(String::as_str).unwrap_or("");
    let rest = args.get(1..).unwrap_or_default();
    let outcome = match command {
        "" | "help" => {
            print!("{USAGE}");
            Ok(())
        }
        "version" => {
            println!("{}", env!("CARGO_PKG_VERSION"));
            Ok(())
        }
        "list" | "ls" => list(rest),
        "path" => path(rest),
        "init" => {
            print!("{}", init_script());
            Ok(())
        }
        other => go(other, rest),
    };
    match outcome {
        Ok(()) => ExitCode::SUCCESS,
        Err(Failed) => ExitCode::FAILURE,
    }
}

/// The shell function and tab completion for bash and zsh, for
/// `eval "$(shtl init)"`. It calls only `shtl path` and `shtl list --names`.
fn init_script() -> String {
    include_str!("init.sh.in")
        .replace("__SHTL_COMMAND_PATTERN__", &COMMANDS.join("|"))
        .replace("__SHTL_COMMANDS__", &COMMANDS.join(" "))
}

fn home() -> String {
    std::env::var("HOME").unwrap_or_default()
}

/// The routes file's routes. Logs the error when it can't be read.
fn load() -> Result<Vec<Route>, Failed> {
    routes::load(&routes::file_path()).map_err(|msg| {
        log::error(&msg);
        Failed
    })
}

fn fail(msg: &str) -> Failed {
    log::error(msg);
    Failed
}

/// The first argument, the route name all route commands need
fn route_name(args: &[String]) -> Result<&str, Failed> {
    args.first()
        .map(String::as_str)
        .ok_or_else(|| fail("Please provide a route name"))
}

/// This host's route with this name
fn find<'a>(all: &'a [Route], name: &str) -> Option<&'a Route> {
    routes::for_host(all, &host::this_host())
        .into_iter()
        .find(|r| r.name == name)
}

/// Logs this host's route names that start with `prefix`, ignoring case,
/// for an unknown name. Never picks one: you type it (or tab-complete it).
/// False when nothing matches.
fn suggest(all: &[Route], prefix: &str) -> bool {
    let prefix = prefix.to_lowercase();
    let names: Vec<&str> = sorted_for_host(all)
        .iter()
        .map(|r| r.name.as_str())
        .filter(|name| name.to_lowercase().starts_with(&prefix))
        .collect();
    if names.is_empty() {
        return false;
    }
    log::info(&format!("Did you mean: {}", names.join(", ")));
    true
}

/// The directory of a route, or of a folder in it. It must exist.
fn route_dir(route: &Route, subdir: Option<&str>) -> Result<String, Failed> {
    let dir = paths::expand(&route.path, &home());
    if !std::path::Path::new(&dir).is_dir() {
        return Err(fail(&format!(
            "Route \"{}\" points to {dir}, which doesn't exist",
            route.name
        )));
    }
    let Some(subdir) = subdir.filter(|s| !s.is_empty()) else {
        return Ok(dir);
    };
    if subdir.starts_with('/') {
        return Err(fail(&format!(
            "\"{subdir}\" must be relative to the route. Leave out the leading \"/\""
        )));
    }
    let dir = paths::normalize(&format!("{dir}/{subdir}"));
    if !std::path::Path::new(&dir).is_dir() {
        return Err(fail(&format!("\"{dir}\" does not exist")));
    }
    Ok(dir)
}

/// Prints only the path, for the shell function and for scripts
fn path(args: &[String]) -> Outcome {
    let name = route_name(args)?;
    let all = load()?;
    let Some(route) = find(&all, name) else {
        log::error(&format!("Route \"{name}\" does not exist"));
        suggest(&all, name);
        return Err(Failed);
    };
    println!("{}", route_dir(route, args.get(1).map(String::as_str))?);
    Ok(())
}

/// `shtl NAME [SUBDIR]`. shtl can't change its shell's directory: the
/// shell function from `shtl init` does the cd. Without it, print the path
/// and say how to set it up.
fn go(name: &str, args: &[String]) -> Outcome {
    let all = load()?;
    let Some(route) = find(&all, name) else {
        log::error(&format!("\"{name}\" is not a shtl command or route"));
        if !suggest(&all, name) {
            print!("{USAGE}");
        }
        return Err(Failed);
    };
    println!("{}", route_dir(route, args.first().map(String::as_str))?);
    log::warn(
        "shtl can't change directory without its shell function. To set it up, run: shtl setup",
    );
    Ok(())
}

/// This host's routes, sorted by name without regard to case
fn sorted_for_host(all: &[Route]) -> Vec<&Route> {
    let mut found = routes::for_host(all, &host::this_host());
    found.sort_by_key(|r| r.name.to_lowercase());
    found
}

/// NAME  PATH columns, with a `(persist)` mark. When the current directory
/// is in a route, a `* ` column marks the closest one (the longest path
/// that contains it; several routes if they share that directory).
fn list(args: &[String]) -> Outcome {
    let all = load()?;
    let found = sorted_for_host(&all);
    if args.first().map(String::as_str) == Some("--names") {
        for route in &found {
            println!("{}", route.name);
        }
        return Ok(());
    }
    if found.is_empty() {
        log::info("No routes yet. Add one with: shtl add NAME [PATH]");
        return Ok(());
    }
    let home = home();
    let expanded: Vec<String> = found
        .iter()
        .map(|r| paths::normalize(&paths::expand(&r.path, &home)))
        .collect();
    let width = found
        .iter()
        .map(|r| r.name.chars().count())
        .max()
        .unwrap_or(0);
    let closest = paths::current_dir().and_then(|cwd| {
        expanded
            .iter()
            .filter(|path| paths::contains(path, &cwd))
            .map(String::len)
            .max()
            .map(|len| (cwd, len))
    });
    for (route, path) in found.iter().zip(&expanded) {
        let mark = match &closest {
            None => "",
            Some((cwd, len)) if path.len() == *len && paths::contains(path, cwd) => "* ",
            Some(_) => "  ",
        };
        let persist = if route.persist { "  (persist)" } else { "" };
        println!("{mark}{:<width$}  {}{persist}", route.name, route.path);
    }
    // A route added before a command of the same name existed can't be jumped to
    for route in found.iter().filter(|r| is_command(&r.name)) {
        let name = &route.name;
        log::warn(&format!(
            "Route \"{name}\" has the same name as a shtl command, so shtl {name} runs the command. Use: cd \"$(shtl path {name})\", or remove it and add it under a new name"
        ));
    }
    Ok(())
}
