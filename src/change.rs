//! What a command changes in the routes file. shtl manages `hosts`: each
//! command changes only this host's route, and routes with the same name,
//! path and persist value share one `[[route]]` with all their hosts.

use crate::routes::Route;

#[derive(Debug, PartialEq)]
pub enum Add {
    /// A route with this name already works on this host
    Exists,
    /// Add this host to the route at this index: it has the same name,
    /// path and persist value
    AddHost(usize),
    /// Write a new route for this host
    New,
}

/// How to add route `name` → `path` (as stored) on `host`
pub fn add(routes: &[Route], name: &str, path: &str, persist: bool, host: &str) -> Add {
    let mut named = routes.iter().filter(|r| r.name == name);
    if named.clone().any(|r| r.applies_to(host)) {
        return Add::Exists;
    }
    match named.find(|r| r.path == path && r.persist == persist && r.hosts.is_some()) {
        Some(route) => Add::AddHost(route.index),
        None => Add::New,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn route(index: usize, name: &str, path: &str, persist: bool, hosts: Option<&[&str]>) -> Route {
        Route {
            name: name.into(),
            path: path.into(),
            persist,
            hosts: hosts.map(|h| h.iter().map(|s| s.to_string()).collect()),
            line: index + 2,
            index,
        }
    }

    #[test]
    fn add_to_an_empty_file_is_new() {
        assert_eq!(add(&[], "work", "~/work", false, "mbp"), Add::New);
    }

    #[test]
    fn add_refuses_a_name_that_works_here() {
        let mine = [route(0, "work", "/x", false, Some(&["MBP"]))];
        assert_eq!(add(&mine, "work", "/y", false, "mbp"), Add::Exists);
        let everywhere = [route(0, "work", "/x", false, None)];
        assert_eq!(add(&everywhere, "work", "/x", false, "mbp"), Add::Exists);
    }

    #[test]
    fn add_joins_another_hosts_route_with_the_same_path_and_persist() {
        let routes = [
            route(0, "other", "~/work", false, Some(&["midgard"])),
            route(1, "work", "~/work", false, Some(&["midgard"])),
        ];
        assert_eq!(
            add(&routes, "work", "~/work", false, "mbp"),
            Add::AddHost(1)
        );
    }

    #[test]
    fn add_makes_a_new_route_when_the_path_or_persist_differs() {
        let routes = [route(0, "work", "/var/tmp/work", false, Some(&["midgard"]))];
        assert_eq!(add(&routes, "work", "~/work", false, "mbp"), Add::New);
        let routes = [route(0, "work", "~/work", true, Some(&["midgard"]))];
        assert_eq!(add(&routes, "work", "~/work", false, "mbp"), Add::New);
    }

    #[test]
    fn add_joins_only_a_route_with_the_same_name() {
        let routes = [route(0, "job", "~/work", false, Some(&["midgard"]))];
        assert_eq!(add(&routes, "work", "~/work", false, "mbp"), Add::New);
    }
}
