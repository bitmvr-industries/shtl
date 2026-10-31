//! `shtl doctor`: problems in routes.toml that can break shtl, with line
//! numbers. The TOML parser finds syntax errors; doctor adds what shtl
//! needs. It only reports: you fix the file in a text editor.

use toml_edit::{Document, Table};

use crate::commands::{is_command, valid_name};
use crate::host;
use crate::routes::VERSION;

#[derive(Debug, PartialEq)]
pub struct Problem {
    pub line: usize,
    pub msg: String,
}

/// Every problem in the routes file text, in file order
pub fn check(text: &str) -> Vec<Problem> {
    let doc = match Document::parse(text) {
        Ok(doc) => doc,
        Err(e) => {
            let start = e.span().map_or(0, |s| s.start).min(text.len());
            let column = text[..start]
                .rsplit('\n')
                .next()
                .map_or(0, |s| s.chars().count())
                + 1;
            return vec![Problem {
                line: line_at(text, Some(start..start)),
                msg: format!("column {column}: {}", e.message().trim()),
            }];
        }
    };
    let mut problems = Vec::new();
    let mut report = |line: usize, msg: String| problems.push(Problem { line, msg });
    let top = doc.as_table();
    let key_line = |table: &Table, key: &str, otherwise: usize| {
        table
            .key(key)
            .and_then(|k| k.span())
            .map_or(otherwise, |span| line_at(text, Some(span)))
    };

    match top.get("version") {
        None => report(1, format!("the file must have: version = {VERSION}")),
        Some(item) if item.as_integer() != Some(VERSION) => report(
            key_line(top, "version", 1),
            format!("version must be {VERSION}. This shtl reads only version {VERSION} files"),
        ),
        Some(_) => {}
    }
    for (key, _) in top.iter() {
        if key != "version" && key != "route" {
            report(
                key_line(top, key, 1),
                format!("\"{key}\" is not a shtl key. The file has a version and [[route]] tables"),
            );
        }
    }

    // Routes good enough to compare for the same name on the same host:
    // (line, name, hosts)
    let mut seen: Vec<(usize, String, Option<Vec<String>>)> = Vec::new();
    match top.get("route") {
        None => {}
        Some(item) => match item.as_array_of_tables() {
            None => report(
                key_line(top, "route", 1),
                "route must be [[route]] tables".into(),
            ),
            Some(tables) => {
                for table in tables.iter() {
                    let line = line_at(text, table.span());
                    let at = |key: &str| key_line(table, key, line);
                    for (key, _) in table.iter() {
                        if !["name", "path", "persist", "hosts"].contains(&key) {
                            report(
                                at(key),
                                format!(
                                    "\"{key}\" is not a route key. The keys are name, path, persist and hosts"
                                ),
                            );
                        }
                    }
                    let name = match table.get("name") {
                        None => {
                            report(line, "the route has no name".into());
                            None
                        }
                        Some(item) => match item.as_str() {
                            None => {
                                report(
                                    at("name"),
                                    "name must be a string, for example: name = \"work\"".into(),
                                );
                                None
                            }
                            Some(name) => {
                                if is_command(name) {
                                    report(
                                        at("name"),
                                        format!(
                                            "route name \"{name}\" is a shtl command, so shtl can't go to this route. Rename it"
                                        ),
                                    );
                                } else if !valid_name(name) {
                                    report(
                                        at("name"),
                                        format!(
                                            "route name \"{name}\" is not valid. Names can't be empty, start with \"-\", or contain spaces or control characters"
                                        ),
                                    );
                                }
                                Some(name)
                            }
                        },
                    };
                    match table.get("path") {
                        None => report(
                            line,
                            format!("route \"{}\" has no path", name.unwrap_or("")),
                        ),
                        Some(item) => match item.as_str() {
                            None => report(
                                at("path"),
                                "path must be a string, for example: path = \"~/work\"".into(),
                            ),
                            Some(path) => {
                                if !(path.starts_with('/') || path == "~" || path.starts_with("~/"))
                                {
                                    report(
                                        at("path"),
                                        format!(
                                            "path \"{path}\" is not absolute. It must start with \"/\" or \"~/\""
                                        ),
                                    );
                                }
                            }
                        },
                    }
                    if table
                        .get("persist")
                        .is_some_and(|item| item.as_bool().is_none())
                    {
                        report(at("persist"), "persist must be true or false".into());
                    }
                    let hosts = match table.get("hosts") {
                        None => Some(None),
                        Some(item) => {
                            let list: Option<Vec<String>> = item.as_array().and_then(|a| {
                                a.iter().map(|v| v.as_str().map(String::from)).collect()
                            });
                            match list {
                                None => {
                                    report(at("hosts"), "hosts must be a list of host names, for example: hosts = [\"midgard\"]".into());
                                    None
                                }
                                Some(list) if list.is_empty() => {
                                    report(at("hosts"), "hosts is empty, so the route works on no machine. Add a host, or remove hosts to make it work on every machine".into());
                                    None
                                }
                                Some(list) => Some(Some(list)),
                            }
                        }
                    };
                    if let (Some(name), Some(hosts)) = (name, hosts) {
                        seen.push((line, name.to_string(), hosts));
                    }
                }
            }
        },
    }

    for (j, (line, name, hosts)) in seen.iter().enumerate() {
        for (other_line, other_name, other_hosts) in &seen[..j] {
            if other_name != name {
                continue;
            }
            match (hosts, other_hosts) {
                (None, None) => {
                    report(
                        *line,
                        format!(
                            "route \"{name}\" is also on line {other_line}, and both work on every machine. Remove one, or give them hosts"
                        ),
                    );
                    break;
                }
                (Some(mine), Some(theirs)) => {
                    if let Some(h) = mine
                        .iter()
                        .find(|h| theirs.iter().any(|t| host::same(t, h)))
                    {
                        report(
                            *line,
                            format!(
                                "route \"{name}\" is also on line {other_line} for host \"{h}\". Take \"{h}\" out of one of them"
                            ),
                        );
                        break;
                    }
                }
                _ => {}
            }
        }
    }
    problems.sort_by_key(|p| p.line);
    problems
}

fn line_at(text: &str, span: Option<std::ops::Range<usize>>) -> usize {
    let start = span.map_or(0, |s| s.start).min(text.len());
    text[..start].matches('\n').count() + 1
}

#[cfg(test)]
mod tests {
    use super::*;

    fn problems(text: &str) -> Vec<(usize, String)> {
        check(text).into_iter().map(|p| (p.line, p.msg)).collect()
    }

    fn one(line: usize, msg: &str) -> Vec<(usize, String)> {
        vec![(line, msg.to_string())]
    }

    const OK: &str = "version = 2\n\n[[route]]\nname = \"work\"\npath = \"~/work\"\npersist = true\nhosts = [\"mbp\"]\n\n[[route]]\nname = \"root\"\npath = \"/\"\n\n[[route]]\nname = \"home\"\npath = \"~\"\n";

    #[test]
    fn a_good_file_has_no_problems() {
        assert_eq!(problems(OK), []);
        assert_eq!(problems("version = 2\n"), []);
    }

    #[test]
    fn a_syntax_error_has_its_line_and_column() {
        assert_eq!(
            problems("version = 2\n[[route]\n"),
            one(2, "column 9: unclosed array table, expected `]`")
        );
    }

    #[test]
    fn version_must_be_2() {
        assert_eq!(problems(""), one(1, "the file must have: version = 2"));
        assert_eq!(
            problems("# routes\nversion = 1\n"),
            one(2, "version must be 2. This shtl reads only version 2 files")
        );
    }

    #[test]
    fn unknown_top_level_keys() {
        assert_eq!(
            problems("version = 2\nroutes = []\n"),
            one(
                2,
                "\"routes\" is not a shtl key. The file has a version and [[route]] tables"
            )
        );
    }

    #[test]
    fn route_must_be_tables() {
        assert_eq!(
            problems("version = 2\nroute = 5\n"),
            one(2, "route must be [[route]] tables")
        );
    }

    #[test]
    fn unknown_route_keys_have_the_keys_line() {
        assert_eq!(
            problems("version = 2\n[[route]]\nname = \"a\"\npath = \"/a\"\npersit = true\n"),
            one(
                5,
                "\"persit\" is not a route key. The keys are name, path, persist and hosts"
            )
        );
    }

    #[test]
    fn name_and_path_must_be_strings() {
        assert_eq!(
            problems("version = 2\n[[route]]\npath = \"/a\"\n"),
            one(2, "the route has no name")
        );
        assert_eq!(
            problems("version = 2\n[[route]]\nname = 1\npath = \"/a\"\n"),
            one(3, "name must be a string, for example: name = \"work\"")
        );
        assert_eq!(
            problems("version = 2\n[[route]]\nname = \"a\"\n"),
            one(2, "route \"a\" has no path")
        );
        assert_eq!(
            problems("version = 2\n[[route]]\nname = \"a\"\npath = [\"/a\"]\n"),
            one(4, "path must be a string, for example: path = \"~/work\"")
        );
    }

    #[test]
    fn names_must_follow_the_rules() {
        assert_eq!(
            problems("version = 2\n[[route]]\nname = \"a b\"\npath = \"/a\"\n"),
            one(
                3,
                "route name \"a b\" is not valid. Names can't be empty, start with \"-\", or contain spaces or control characters"
            )
        );
        assert_eq!(
            problems("version = 2\n[[route]]\nname = \"ls\"\npath = \"/a\"\n"),
            one(
                3,
                "route name \"ls\" is a shtl command, so shtl can't go to this route. Rename it"
            )
        );
    }

    #[test]
    fn paths_must_be_absolute() {
        assert_eq!(
            problems(
                "version = 2\n[[route]]\nname = \"a\"\npath = \"work\"\n[[route]]\nname = \"b\"\npath = \"~work\"\n"
            ),
            vec![
                (
                    4,
                    "path \"work\" is not absolute. It must start with \"/\" or \"~/\"".to_string()
                ),
                (
                    7,
                    "path \"~work\" is not absolute. It must start with \"/\" or \"~/\""
                        .to_string()
                ),
            ]
        );
    }

    #[test]
    fn persist_and_hosts_need_the_right_types() {
        assert_eq!(
            problems("version = 2\n[[route]]\nname = \"a\"\npath = \"/a\"\npersist = \"yes\"\n"),
            one(5, "persist must be true or false")
        );
        assert_eq!(
            problems("version = 2\n[[route]]\nname = \"a\"\npath = \"/a\"\nhosts = \"mbp\"\n"),
            one(
                5,
                "hosts must be a list of host names, for example: hosts = [\"midgard\"]"
            )
        );
        assert_eq!(
            problems("version = 2\n[[route]]\nname = \"a\"\npath = \"/a\"\nhosts = []\n"),
            one(
                5,
                "hosts is empty, so the route works on no machine. Add a host, or remove hosts to make it work on every machine"
            )
        );
    }

    #[test]
    fn two_routes_with_a_name_for_the_same_host() {
        let both_everywhere = "version = 2\n[[route]]\nname = \"a\"\npath = \"/a\"\n[[route]]\nname = \"a\"\npath = \"/b\"\n";
        assert_eq!(
            problems(both_everywhere),
            one(
                5,
                "route \"a\" is also on line 2, and both work on every machine. Remove one, or give them hosts"
            )
        );
        let shared_host = "version = 2\n[[route]]\nname = \"a\"\npath = \"/a\"\nhosts = [\"x\", \"MBP\"]\n[[route]]\nname = \"a\"\npath = \"/b\"\nhosts = [\"mbp\"]\n";
        assert_eq!(
            problems(shared_host),
            one(
                6,
                "route \"a\" is also on line 2 for host \"mbp\". Take \"mbp\" out of one of them"
            )
        );
    }

    #[test]
    fn a_host_route_may_override_a_route_with_no_hosts() {
        let text = "version = 2\n[[route]]\nname = \"a\"\npath = \"/a\"\n[[route]]\nname = \"a\"\npath = \"/b\"\nhosts = [\"mbp\"]\n[[route]]\nname = \"a\"\npath = \"/c\"\nhosts = [\"midgard\"]\n";
        assert_eq!(problems(text), []);
    }

    #[test]
    fn reports_every_problem_in_file_order() {
        let text = "version = 2\nextra = 1\n[[route]]\nname = \"-a\"\npath = \"rel\"\n";
        assert_eq!(
            problems(text).iter().map(|p| p.0).collect::<Vec<_>>(),
            [2, 4, 5]
        );
    }
}
