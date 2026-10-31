//! The routes file, `routes.toml`:
//!
//! ```toml
//! version = 2
//!
//! [[route]]
//! name = "work"
//! path = "~/work"
//! hosts = ["midgard"]   # optional: no hosts means every machine
//! persist = true        # optional
//! ```
//!
//! The format version matches shtl's major version. Bump both together.

use std::path::{Path, PathBuf};

use toml_edit::{Document, Item, Table};

use crate::host;

pub const VERSION: i64 = 2;

#[derive(Debug, Clone, PartialEq)]
pub struct Route {
    pub name: String,
    /// As stored: absolute, or `~` / `~/...`
    pub path: String,
    pub persist: bool,
    /// None: the route works on every machine
    pub hosts: Option<Vec<String>>,
    /// Line of the route's `[[route]]` header, from 1
    pub line: usize,
    /// Position in the file's `[[route]]` list, from 0
    pub index: usize,
}

#[derive(Debug, PartialEq)]
pub enum ParseError {
    /// Not valid TOML. The message has the line and column.
    Syntax(String),
    /// `version` is missing or isn't 2
    Version,
    /// A route that shtl can't use
    Invalid { line: usize, msg: String },
}

impl Route {
    /// True when `hosts` names this host
    pub fn lists_host(&self, host: &str) -> bool {
        self.hosts
            .as_ref()
            .is_some_and(|hosts| hosts.iter().any(|h| host::same(h, host)))
    }

    /// True when the route works on this host
    pub fn applies_to(&self, host: &str) -> bool {
        self.hosts.is_none() || self.lists_host(host)
    }
}

pub fn parse(text: &str) -> Result<Vec<Route>, ParseError> {
    let doc = Document::parse(text).map_err(|e| ParseError::Syntax(e.to_string()))?;
    if doc.get("version").and_then(Item::as_integer) != Some(VERSION) {
        return Err(ParseError::Version);
    }
    let Some(item) = doc.get("route") else {
        return Ok(vec![]);
    };
    let Some(tables) = item.as_array_of_tables() else {
        return Err(ParseError::Invalid {
            line: line_at(text, item.span()),
            msg: "route must be [[route]] tables".into(),
        });
    };
    tables
        .iter()
        .enumerate()
        .map(|(index, table)| parse_route(table, line_at(text, table.span()), index))
        .collect()
}

fn parse_route(table: &Table, line: usize, index: usize) -> Result<Route, ParseError> {
    let invalid = |msg: &str| ParseError::Invalid {
        line,
        msg: msg.into(),
    };
    let name = table
        .get("name")
        .and_then(Item::as_str)
        .ok_or_else(|| invalid("name must be a string, for example: name = \"work\""))?;
    let path = table
        .get("path")
        .and_then(Item::as_str)
        .ok_or_else(|| invalid("path must be a string, for example: path = \"~/work\""))?;
    let persist = match table.get("persist") {
        None => false,
        Some(item) => item
            .as_bool()
            .ok_or_else(|| invalid("persist must be true or false"))?,
    };
    let hosts = match table.get("hosts") {
        None => None,
        Some(item) => Some(
            item.as_array()
                .and_then(|array| array.iter().map(|v| v.as_str().map(String::from)).collect())
                .ok_or_else(|| {
                    invalid(
                        "hosts must be a list of host names, for example: hosts = [\"midgard\"]",
                    )
                })?,
        ),
    };
    Ok(Route {
        name: name.into(),
        path: path.into(),
        persist,
        hosts,
        line,
        index,
    })
}

/// The line (from 1) where a span starts
fn line_at(text: &str, span: Option<std::ops::Range<usize>>) -> usize {
    let start = span.map_or(0, |s| s.start).min(text.len());
    text[..start].matches('\n').count() + 1
}

/// The routes that work on this host, one per name, in file order. A route
/// that lists this host wins over a route with no hosts. If two routes are
/// at the same level (a problem `shtl doctor` reports), the first one wins.
pub fn for_host<'a>(routes: &'a [Route], host: &str) -> Vec<&'a Route> {
    let mut found: Vec<&Route> = Vec::new();
    for route in routes.iter().filter(|r| r.applies_to(host)) {
        match found.iter_mut().find(|r| r.name == route.name) {
            None => found.push(route),
            Some(kept) => {
                if route.lists_host(host) && !kept.lists_host(host) {
                    *kept = route;
                }
            }
        }
    }
    found.sort_by_key(|r| r.line);
    found
}

/// `$XDG_CONFIG_HOME/shtl/routes.toml`, or `~/.config/shtl/routes.toml`
pub fn file_path() -> PathBuf {
    let config = match std::env::var("XDG_CONFIG_HOME") {
        Ok(dir) if !dir.is_empty() => PathBuf::from(dir),
        _ => PathBuf::from(std::env::var("HOME").unwrap_or_default()).join(".config"),
    };
    config.join("shtl").join("routes.toml")
}

/// Reads the routes file. No file means no routes: reading never creates
/// it. Errors are messages for the user.
pub fn load(file: &Path) -> Result<Vec<Route>, String> {
    match read_text(file)? {
        None => Ok(vec![]),
        Some(text) => parse_file(file, &text),
    }
}

/// The routes file's text, or None when there is no file
pub fn read_text(file: &Path) -> Result<Option<String>, String> {
    match std::fs::read_to_string(file) {
        Ok(text) => Ok(Some(text)),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(format!("Could not read {}: {e}", file.display())),
    }
}

/// `parse`, with errors as messages for the user that name the file
pub fn parse_file(file: &Path, text: &str) -> Result<Vec<Route>, String> {
    let shown = file.display();
    parse(text).map_err(|e| match e {
        ParseError::Syntax(msg) => format!("{shown} is not valid TOML. {}", msg.trim_end()),
        ParseError::Version => format!(
            "{shown} is not a shtl {VERSION} routes file. It must have the line: version = {VERSION}. To find the problem, run: shtl doctor"
        ),
        ParseError::Invalid { line, msg } => {
            format!("{shown}, line {line}: {msg}. To find all problems, run: shtl doctor")
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn route(name: &str, path: &str, hosts: Option<&[&str]>, line: usize) -> Route {
        Route {
            name: name.into(),
            path: path.into(),
            persist: false,
            hosts: hosts.map(|h| h.iter().map(|s| s.to_string()).collect()),
            line,
            index: 0,
        }
    }

    #[test]
    fn parses_routes_with_their_lines() {
        let text = "version = 2\n\n# Work\n[[route]]\nname = \"work\"\npath = \"~/work\"\n\n[[route]]\nname = \"nas\"\npath = \"/Volumes/nas\"\npersist = true\nhosts = [\"midgard\", \"mbp\"]\n";
        let routes = parse(text).unwrap();
        assert_eq!(
            routes,
            vec![
                route("work", "~/work", None, 4),
                Route {
                    persist: true,
                    index: 1,
                    ..route("nas", "/Volumes/nas", Some(&["midgard", "mbp"]), 8)
                },
            ]
        );
    }

    #[test]
    fn a_file_with_only_the_version_has_no_routes() {
        assert_eq!(parse("version = 2\n"), Ok(vec![]));
    }

    #[test]
    fn version_must_be_2() {
        assert_eq!(parse(""), Err(ParseError::Version));
        assert_eq!(parse("version = 1\n"), Err(ParseError::Version));
        assert_eq!(parse("version = \"2\"\n"), Err(ParseError::Version));
    }

    #[test]
    fn syntax_errors_name_the_line() {
        match parse("version = 2\n[[route]\n") {
            Err(ParseError::Syntax(msg)) => assert!(msg.contains("line 2"), "{msg}"),
            other => panic!("{other:?}"),
        }
    }

    fn invalid(text: &str) -> (usize, String) {
        match parse(text) {
            Err(ParseError::Invalid { line, msg }) => (line, msg),
            other => panic!("{other:?}"),
        }
    }

    #[test]
    fn a_route_needs_a_string_name_and_path() {
        let ok = "version = 2\n[[route]]\nname = \"a\"\npath = \"/a\"\n";
        assert_eq!(invalid(&format!("{ok}[[route]]\npath = \"/b\"\n")).0, 5);
        assert!(
            invalid(&format!("{ok}[[route]]\npath = \"/b\"\n"))
                .1
                .contains("name")
        );
        assert!(
            invalid("version = 2\n[[route]]\nname = 3\npath = \"/b\"\n")
                .1
                .contains("name")
        );
        assert!(
            invalid("version = 2\n[[route]]\nname = \"b\"\n")
                .1
                .contains("path")
        );
    }

    #[test]
    fn persist_and_hosts_need_the_right_types() {
        assert!(
            invalid("version = 2\n[[route]]\nname = \"b\"\npath = \"/b\"\npersist = \"yes\"\n")
                .1
                .contains("persist")
        );
        assert!(
            invalid("version = 2\n[[route]]\nname = \"b\"\npath = \"/b\"\nhosts = \"midgard\"\n")
                .1
                .contains("hosts")
        );
        assert!(
            invalid("version = 2\n[[route]]\nname = \"b\"\npath = \"/b\"\nhosts = [1]\n")
                .1
                .contains("hosts")
        );
    }

    #[test]
    fn route_must_be_route_tables() {
        assert!(invalid("version = 2\nroute = 5\n").1.contains("[[route]]"));
    }

    #[test]
    fn a_route_without_hosts_applies_everywhere() {
        let r = route("a", "/a", None, 1);
        assert!(r.applies_to("anything"));
        assert!(!r.lists_host("anything"));
    }

    #[test]
    fn a_route_with_hosts_applies_only_there_ignoring_case() {
        let r = route("a", "/a", Some(&["Midgard", "mbp"]), 1);
        assert!(r.applies_to("midgard"));
        assert!(r.lists_host("MBP"));
        assert!(!r.applies_to("asgard"));
        assert!(!route("a", "/a", Some(&[]), 1).applies_to("midgard"));
    }

    fn names_and_lines(routes: Vec<&Route>) -> Vec<(&str, usize)> {
        routes.iter().map(|r| (r.name.as_str(), r.line)).collect()
    }

    #[test]
    fn for_host_hides_other_hosts_routes() {
        let routes = [
            route("a", "/a", Some(&["asgard"]), 1),
            route("b", "/b", None, 2),
            route("c", "/c", Some(&["midgard"]), 3),
        ];
        assert_eq!(
            names_and_lines(for_host(&routes, "midgard")),
            [("b", 2), ("c", 3)]
        );
    }

    #[test]
    fn for_host_prefers_a_host_route_over_a_no_host_route() {
        let host_first = [
            route("d", "/x", Some(&["midgard"]), 1),
            route("d", "/y", None, 2),
        ];
        let host_last = [
            route("d", "/y", None, 1),
            route("d", "/x", Some(&["midgard"]), 2),
        ];
        assert_eq!(for_host(&host_first, "midgard")[0].path, "/x");
        assert_eq!(for_host(&host_last, "midgard")[0].path, "/x");
        assert_eq!(for_host(&host_last, "midgard").len(), 1);
        assert_eq!(for_host(&host_last, "mbp")[0].path, "/y");
    }

    #[test]
    fn for_host_takes_the_first_of_two_at_the_same_level() {
        let routes = [route("d", "/x", None, 1), route("d", "/y", None, 2)];
        assert_eq!(names_and_lines(for_host(&routes, "midgard")), [("d", 1)]);
    }

    #[test]
    fn load_with_no_file_has_no_routes() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("routes.toml");
        assert_eq!(load(&file), Ok(vec![]));
        assert!(!file.exists());
    }

    #[test]
    fn load_errors_name_the_file() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("routes.toml");
        std::fs::write(&file, "version = 1\n").unwrap();
        let msg = load(&file).unwrap_err();
        assert!(msg.contains(&file.display().to_string()), "{msg}");
        assert!(msg.contains("shtl doctor"), "{msg}");
    }
}
