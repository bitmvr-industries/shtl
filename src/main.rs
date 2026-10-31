mod log;

use std::process::ExitCode;

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

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let command = args.first().map(String::as_str).unwrap_or("");

    match command {
        "" | "help" => {
            print!("{USAGE}");
            ExitCode::SUCCESS
        }
        "version" => {
            println!("{}", env!("CARGO_PKG_VERSION"));
            ExitCode::SUCCESS
        }
        other => {
            log::error(&format!("\"{other}\" is not a shtl command or route"));
            print!("{USAGE}");
            ExitCode::FAILURE
        }
    }
}
