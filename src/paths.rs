//! Paths as shtl stores them. A path under the home directory is stored as
//! `~` or `~/...`, so one routes file works on machines with different
//! homes (/Users/me, /home/me). The `~` here is the literal stored text.

/// A stored path as a real path: `~` and `~/...` become the home directory.
pub fn expand(stored: &str, home: &str) -> String {
    let home = home.trim_end_matches('/');
    if stored == "~" {
        if home.is_empty() {
            "/".to_string()
        } else {
            home.to_string()
        }
    } else if let Some(rest) = stored.strip_prefix("~/") {
        format!("{home}/{rest}")
    } else {
        stored.to_string()
    }
}

/// A real path as it is stored: a path in the home directory becomes `~/...`.
pub fn contract(path: &str, home: &str) -> String {
    let home = home.trim_end_matches('/');
    if home.is_empty() {
        return path.to_string();
    }
    if path == home {
        return "~".to_string();
    }
    match path
        .strip_prefix(home)
        .and_then(|rest| rest.strip_prefix('/'))
    {
        Some(rest) => format!("~/{rest}"),
        None => path.to_string(),
    }
}

/// Removes ".", ".." and extra slashes from an absolute path, without
/// touching the filesystem (the directory may not exist yet, and symlinks
/// stay as typed, the same way `pwd` shows them).
pub fn normalize(path: &str) -> String {
    let mut kept: Vec<&str> = Vec::new();
    for part in path.split('/') {
        match part {
            "" | "." => {}
            ".." => {
                kept.pop();
            }
            _ => kept.push(part),
        }
    }
    format!("/{}", kept.join("/"))
}

/// True when directory `dir` is `route` or inside it.
pub fn contains(route: &str, dir: &str) -> bool {
    route == "/"
        || dir == route
        || dir
            .strip_prefix(route)
            .is_some_and(|rest| rest.starts_with('/'))
}

/// The current directory the way `pwd` shows it: the shell's `$PWD` when it
/// is this directory (keeps symlinks as typed), else the real path. None
/// when the directory was deleted.
pub fn current_dir() -> Option<String> {
    use std::os::unix::fs::MetadataExt;
    let real = std::env::current_dir().ok()?;
    if let Ok(pwd) = std::env::var("PWD")
        && pwd.starts_with('/')
        && let (Ok(a), Ok(b)) = (std::fs::metadata(&pwd), std::fs::metadata(&real))
        && (a.dev(), a.ino()) == (b.dev(), b.ino())
    {
        return Some(normalize(&pwd));
    }
    Some(real.to_string_lossy().into_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn expand_replaces_a_leading_tilde_only() {
        assert_eq!(expand("~", "/home/me"), "/home/me");
        assert_eq!(expand("~/work", "/home/me"), "/home/me/work");
        assert_eq!(expand("~/work", "/home/me/"), "/home/me/work");
        assert_eq!(expand("/srv/~/x", "/home/me"), "/srv/~/x");
        assert_eq!(expand("~other/x", "/home/me"), "~other/x");
    }

    #[test]
    fn expand_with_no_home_makes_tilde_the_root() {
        assert_eq!(expand("~", ""), "/");
        assert_eq!(expand("~", "/"), "/");
    }

    #[test]
    fn contract_stores_home_paths_with_a_tilde() {
        assert_eq!(contract("/home/me", "/home/me"), "~");
        assert_eq!(contract("/home/me/work", "/home/me"), "~/work");
        assert_eq!(contract("/home/me/work", "/home/me/"), "~/work");
    }

    #[test]
    fn contract_keeps_other_paths() {
        assert_eq!(contract("/home/meow", "/home/me"), "/home/meow");
        assert_eq!(contract("/srv", "/home/me"), "/srv");
        assert_eq!(contract("/home/me/x", ""), "/home/me/x");
        assert_eq!(contract("/x", "/"), "/x");
    }

    #[test]
    fn normalize_removes_dots_and_extra_slashes() {
        assert_eq!(normalize("/a//b/./c/"), "/a/b/c");
        assert_eq!(normalize("/a/b/../c"), "/a/c");
        assert_eq!(normalize("/.."), "/");
        assert_eq!(normalize("/"), "/");
        assert_eq!(normalize("/a/../../b"), "/b");
    }

    #[test]
    fn contains_matches_whole_path_parts() {
        assert!(contains("/a", "/a"));
        assert!(contains("/a", "/a/b"));
        assert!(contains("/", "/a"));
        assert!(!contains("/a", "/ab"));
        assert!(!contains("/a/b", "/a"));
    }
}
