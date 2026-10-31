//! What a command changes in the routes file. shtl manages `hosts`: each
//! command changes only this host's route, and routes with the same name,
//! path and persist value share one `[[route]]` with all their hosts.

use crate::host;
use crate::routes::Route;
use crate::store::NewRoute;

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

/// One change to the routes file. Indexes are positions in the file's
/// `[[route]]` list, as read.
#[derive(Debug, Clone, PartialEq)]
pub enum Edit {
    /// Set the path and persist of the route at `index`
    Rewrite {
        index: usize,
        path: String,
        persist: bool,
    },
    /// Add this host to the hosts of the route at `index`
    AddHost { index: usize },
    /// Take this host out of the hosts of the route at `index`
    RemoveHost { index: usize },
    /// Delete the route at `index`
    Delete { index: usize },
    /// Write a new route directly after the route at `after`
    Insert { after: usize, route: NewRoute },
}

/// Points this host's route `current` at `path` with `persist`, without
/// changing the route on any other host:
///
/// - Only this host in its hosts: change it in place.
/// - This host and others: take this host out, and give it its own route.
/// - No hosts (works everywhere): leave it, and give this host its own
///   route, which wins here.
///
/// "Its own route" is another route with the same name, path and persist
/// when one exists (this host joins it), else a new one after `current`.
pub fn retarget(
    routes: &[Route],
    current: &Route,
    path: &str,
    persist: bool,
    host: &str,
) -> Vec<Edit> {
    if current.path == path && current.persist == persist {
        return vec![];
    }
    let index = current.index;
    let join = routes.iter().find(|r| {
        r.index != index
            && r.name == current.name
            && r.path == path
            && r.persist == persist
            && r.hosts.is_some()
    });
    let mut edits = Vec::new();
    match &current.hosts {
        None => {}
        Some(hosts) if hosts.iter().all(|h| host::same(h, host)) => {
            if join.is_none() {
                return vec![Edit::Rewrite {
                    index,
                    path: path.into(),
                    persist,
                }];
            }
            edits.push(Edit::Delete { index });
        }
        Some(_) => edits.push(Edit::RemoveHost { index }),
    }
    edits.push(match join {
        Some(route) => Edit::AddHost { index: route.index },
        None => Edit::Insert {
            after: index,
            route: NewRoute {
                name: current.name.clone(),
                path: path.into(),
                persist,
                hosts: vec![host.into()],
            },
        },
    });
    edits
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

    fn mine(after: usize, path: &str, persist: bool) -> Edit {
        Edit::Insert {
            after,
            route: NewRoute {
                name: "work".into(),
                path: path.into(),
                persist,
                hosts: vec!["mbp".into()],
            },
        }
    }

    #[test]
    fn retarget_changes_a_route_only_this_host_has_in_place() {
        let routes = [route(0, "work", "/old", false, Some(&["MBP"]))];
        assert_eq!(
            retarget(&routes, &routes[0], "/new", true, "mbp"),
            [Edit::Rewrite {
                index: 0,
                path: "/new".into(),
                persist: true
            }]
        );
    }

    #[test]
    fn retarget_splits_this_host_off_a_shared_route() {
        let routes = [route(0, "work", "/old", false, Some(&["midgard", "mbp"]))];
        assert_eq!(
            retarget(&routes, &routes[0], "/new", false, "mbp"),
            [Edit::RemoveHost { index: 0 }, mine(0, "/new", false)]
        );
    }

    #[test]
    fn retarget_overrides_a_route_with_no_hosts() {
        let routes = [route(0, "work", "/old", false, None)];
        assert_eq!(
            retarget(&routes, &routes[0], "/new", false, "mbp"),
            [mine(0, "/new", false)]
        );
    }

    #[test]
    fn retarget_joins_a_matching_route_instead_of_writing_one() {
        let routes = [
            route(0, "work", "/old", false, Some(&["midgard", "mbp"])),
            route(1, "work", "/new", false, Some(&["asgard"])),
        ];
        assert_eq!(
            retarget(&routes, &routes[0], "/new", false, "mbp"),
            [Edit::RemoveHost { index: 0 }, Edit::AddHost { index: 1 }]
        );
        let routes = [
            route(0, "work", "/new", false, Some(&["asgard"])),
            route(1, "work", "/old", false, Some(&["mbp"])),
        ];
        assert_eq!(
            retarget(&routes, &routes[1], "/new", false, "mbp"),
            [Edit::Delete { index: 1 }, Edit::AddHost { index: 0 }]
        );
        let routes = [
            route(0, "work", "/old", false, None),
            route(1, "work", "/new", false, Some(&["asgard"])),
        ];
        assert_eq!(
            retarget(&routes, &routes[0], "/new", false, "mbp"),
            [Edit::AddHost { index: 1 }]
        );
    }

    #[test]
    fn retarget_joins_only_a_route_with_the_same_persist_and_hosts() {
        let routes = [
            route(0, "work", "/old", false, Some(&["mbp"])),
            route(1, "work", "/new", true, Some(&["asgard"])),
            route(2, "work", "/new", false, None),
            route(3, "job", "/new", false, Some(&["asgard"])),
        ];
        assert_eq!(
            retarget(&routes, &routes[0], "/new", false, "mbp"),
            [Edit::Rewrite {
                index: 0,
                path: "/new".into(),
                persist: false
            }]
        );
    }

    #[test]
    fn retarget_to_the_same_path_and_persist_changes_nothing() {
        let routes = [route(0, "work", "/a", false, Some(&["midgard", "mbp"]))];
        assert_eq!(retarget(&routes, &routes[0], "/a", false, "mbp"), []);
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
