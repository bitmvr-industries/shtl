//! Reads the command line and runs the command.

use std::process::ExitCode;

use crate::commands::{COMMANDS, is_command, valid_name};
use crate::routes::{self, Route};
use crate::store::{NewRoute, Store};
use crate::{change, host, log, paths};

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
        "add" => add(rest),
        "update" => update(rest),
        "remove" | "rm" => remove(rest),
        "persist" => persist(rest),
        "clean" => clean(),
        "doctor" => doctor(),
        "setup" => crate::setup::setup().map_err(|msg| fail(&msg)),
        "unsetup" => crate::setup::unsetup().map_err(|msg| fail(&msg)),
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
fn route_name(first: Option<&str>) -> Result<&str, Failed> {
    first.ok_or_else(|| fail("Please provide a route name"))
}

fn open_store() -> Result<Store, Failed> {
    Store::open(&routes::file_path()).map_err(|msg| fail(&msg))
}

/// The path a route stores, as a real path: PATH (absolute, or ~/...) or
/// the current directory, normalized
fn resolve_path(given: Option<&str>) -> Result<String, Failed> {
    let path = match given {
        Some(given) => {
            let path = paths::expand(given, &home());
            if !path.starts_with('/') {
                return Err(fail(&format!(
                    "\"{given}\" is not an absolute path. Use a full path starting with \"/\", or leave PATH out to use the current directory"
                )));
            }
            path
        }
        None => paths::current_dir().ok_or_else(|| {
            fail("The current directory does not exist anymore. Give a PATH, or cd to an existing directory")
        })?,
    };
    Ok(paths::normalize(&path))
}

/// A route points to a directory. Only a persistent route can point to one
/// that doesn't exist yet.
fn check_dir(path: &str, persist: bool, hint: &str) -> Outcome {
    let meta = std::fs::metadata(path);
    if meta.as_ref().is_ok_and(|m| !m.is_dir()) {
        return Err(fail(&format!("\"{path}\" is not a directory")));
    }
    if !persist && meta.is_err() {
        return Err(fail(&format!(
            "\"{path}\" does not exist. Only a persistent route can point to a missing directory. {hint}"
        )));
    }
    Ok(())
}

/// Warns about this host's other routes to the same directory
fn warn_shared_dir(all: &[Route], name: &str, path: &str) {
    let home = home();
    for route in sorted_for_host(all) {
        if route.name != name && paths::normalize(&paths::expand(&route.path, &home)) == path {
            log::warn(&format!("Route \"{}\" also points to {path}", route.name));
        }
    }
}

/// `add NAME [PATH] [-p|--persist]`. Records this host: joins another
/// host's route with the same name, path and persist, or writes a new one.
fn add(args: &[String]) -> Outcome {
    let persist = args.iter().any(|a| a == "-p" || a == "--persist");
    let words: Vec<&str> = args
        .iter()
        .map(String::as_str)
        .filter(|a| *a != "-p" && *a != "--persist")
        .collect();
    let name = route_name(words.first().copied())?;
    let mut store = open_store()?;
    if !valid_name(name) {
        return Err(fail(&format!(
            "Route names can't be empty, start with \"-\", contain spaces or control characters, or be a shtl command ({})",
            COMMANDS.join(", ")
        )));
    }
    let exists = || {
        fail(&format!(
            "Route \"{name}\" already exists. To change its path, run: shtl update {name} PATH"
        ))
    };
    if find(&store.routes, name).is_some() {
        return Err(exists());
    }
    let path = resolve_path(words.get(1).copied())?;
    check_dir(
        &path,
        persist,
        "To add a route for a directory that will exist later, use --persist",
    )?;
    let stored = paths::contract(&path, &home());
    let host = host::this_host();
    match change::add(&store.routes, name, &stored, persist, &host) {
        change::Add::Exists => return Err(exists()),
        change::Add::AddHost(index) => store.add_host(index, &host),
        change::Add::New => store.push(&NewRoute {
            name: name.into(),
            path: stored,
            persist,
            hosts: vec![host],
        }),
    }
    store.save().map_err(|msg| fail(&msg))?;
    warn_shared_dir(&store.routes, name, &path);
    Ok(())
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

/// This host's route `name`, for a command that changes it. Logs an error
/// with suggestions when it doesn't exist.
fn find_to_change(all: &[Route], name: &str, verb: &str) -> Result<Route, Failed> {
    match find(all, name) {
        Some(route) => Ok(route.clone()),
        None => {
            log::error(&format!(
                "Could not {verb} route \"{name}\". The route does not exist"
            ));
            suggest(all, name);
            Err(Failed)
        }
    }
}

/// Makes the edits for this host and saves, when there are any
fn save_edits(store: &mut Store, edits: &[change::Edit], host: &str) -> Outcome {
    if edits.is_empty() {
        return Ok(());
    }
    store.apply(edits, host);
    store.save().map_err(|msg| fail(&msg))
}

/// `update NAME [PATH]`: points this host's route at PATH and keeps its
/// persist value. Never changes the route on another host.
fn update(args: &[String]) -> Outcome {
    let name = route_name(args.first().map(String::as_str))?;
    let mut store = open_store()?;
    let current = find_to_change(&store.routes, name, "update")?;
    let path = resolve_path(args.get(1).map(String::as_str))?;
    check_dir(
        &path,
        current.persist,
        &format!(
            "To make this route persistent, run: shtl persist {name}. Then run this update again"
        ),
    )?;
    let stored = paths::contract(&path, &home());
    let host = host::this_host();
    let edits = change::retarget(&store.routes, &current, &stored, current.persist, &host);
    save_edits(&mut store, &edits, &host)?;
    warn_shared_dir(&store.routes, name, &path);
    log::info(&format!("Route \"{name}\" now points to {path}"));
    Ok(())
}

/// `remove NAME`: removes this host's route only
fn remove(args: &[String]) -> Outcome {
    let name = route_name(args.first().map(String::as_str))?;
    let mut store = open_store()?;
    let current = find_to_change(&store.routes, name, "remove")?;
    let host = host::this_host();
    save_edits(&mut store, &[change::remove(&current, &host)], &host)?;
    if current.hosts.is_none() {
        log::info(&format!(
            "Route \"{name}\" had no hosts, so it is removed on every machine"
        ));
    }
    Ok(())
}

/// `persist NAME`: turns persist on or off for this host's route only.
/// Turning it off needs the directory, since only a persistent route can
/// point to a missing one.
fn persist(args: &[String]) -> Outcome {
    let name = route_name(args.first().map(String::as_str))?;
    let mut store = open_store()?;
    let current = find_to_change(&store.routes, name, "persist")?;
    if current.persist {
        check_dir(
            &paths::expand(&current.path, &home()),
            false,
            &format!(
                "Point it at an existing directory with: shtl update {name} PATH, or remove it"
            ),
        )?;
    }
    let host = host::this_host();
    let edits = change::retarget(
        &store.routes,
        &current,
        &current.path,
        !current.persist,
        &host,
    );
    save_edits(&mut store, &edits, &host)?;
    if current.persist {
        log::info(&format!("Route \"{name}\" is no longer persistent"));
    } else {
        log::info(&format!(
            "Route \"{name}\" is now persistent. Clean will skip it"
        ));
    }
    Ok(())
}

/// `clean`: a checklist of this host's routes to directories that aren't
/// there, then removes the selected ones for this host only. Persistent
/// routes are skipped, and so are routes with no hosts: a directory that is
/// missing on one machine says nothing about the others.
fn clean() -> Outcome {
    use std::io::IsTerminal;

    let mut store = open_store()?;
    let mine = sorted_for_host(&store.routes);
    if mine.is_empty() {
        log::info("No routes to clean. Add one with: shtl add NAME [PATH]");
        return Ok(());
    }
    let home = home();
    let gone: Vec<Route> = mine
        .into_iter()
        .filter(|r| r.hosts.is_some() && !r.persist)
        .filter(|r| !std::path::Path::new(&paths::expand(&r.path, &home)).is_dir())
        .cloned()
        .collect();
    if gone.is_empty() {
        log::info("All routes point to existing directories");
        return Ok(());
    }
    if !std::io::stdin().is_terminal() || !std::io::stderr().is_terminal() {
        return Err(fail("Clean needs an interactive terminal"));
    }
    let rows: Vec<(String, String)> = gone
        .iter()
        .map(|r| (r.name.clone(), r.path.clone()))
        .collect();
    let done = crate::clean::run(&rows).map_err(|e| fail(&format!("Clean stopped: {e}")))?;
    match done {
        crate::clean::Done::Cancel => {
            log::info("Clean cancelled. No routes were removed");
            Ok(())
        }
        crate::clean::Done::Interrupt => std::process::exit(130),
        crate::clean::Done::Remove(picked) => {
            let host = host::this_host();
            let edits: Vec<change::Edit> = picked
                .iter()
                .map(|i| change::remove(&gone[*i], &host))
                .collect();
            save_edits(&mut store, &edits, &host)?;
            log::info(&format!("Removed {} route(s)", picked.len()));
            Ok(())
        }
    }
}

/// `doctor`: reports problems in the routes file, with line numbers. Reads
/// the text itself, so it works on a file that other commands reject.
fn doctor() -> Outcome {
    let file = routes::file_path();
    println!("This host: {}", host::this_host());
    let Some(text) = routes::read_text(&file).map_err(|msg| fail(&msg))? else {
        println!("There is no routes file yet. Nothing to check");
        return Ok(());
    };
    let problems = crate::doctor::check(&text);
    if problems.is_empty() {
        println!("No problems found in {}", file.display());
        return Ok(());
    }
    println!("Problems found in {}:", file.display());
    for problem in problems {
        // A syntax error's message starts with its column
        let sep = if problem.msg.starts_with("column ") {
            ", "
        } else {
            ": "
        };
        println!("  Line {}{sep}{}", problem.line, problem.msg);
    }
    Err(Failed)
}

/// Prints only the path, for the shell function and for scripts
fn path(args: &[String]) -> Outcome {
    let name = route_name(args.first().map(String::as_str))?;
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
