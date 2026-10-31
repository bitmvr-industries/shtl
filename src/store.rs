//! Changes to the routes file. Each change edits only its own route in the
//! TOML document, so comments, blank lines and order stay.

use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

use toml_edit::{Array, ArrayOfTables, DocumentMut, Item, Table, Value, value};

use crate::change::Edit;
use crate::host;
use crate::routes::{self, Route};

/// A new route, as it is written
#[derive(Debug, Clone, PartialEq)]
pub struct NewRoute {
    pub name: String,
    /// As stored: absolute, or `~` / `~/...`
    pub path: String,
    pub persist: bool,
    pub hosts: Vec<String>,
}

#[derive(Debug)]
pub struct Store {
    pub file: PathBuf,
    pub routes: Vec<Route>,
    doc: DocumentMut,
}

impl Store {
    /// Reads the routes file for a change. No file: an empty one, which is
    /// written on save. Errors are messages for the user.
    pub fn open(file: &Path) -> Result<Store, String> {
        let (routes, text) = match routes::read_text(file)? {
            None => (vec![], format!("version = {}\n", routes::VERSION)),
            Some(text) => (routes::parse_file(file, &text)?, text),
        };
        let doc = text
            .parse::<DocumentMut>()
            .map_err(|e| format!("{} is not valid TOML. {e}", file.display()))?;
        Ok(Store {
            file: file.to_path_buf(),
            routes,
            doc,
        })
    }

    /// Adds a route at the end of the file, after a blank line
    pub fn push(&mut self, route: &NewRoute) {
        let table = new_table(route);
        let list = self
            .doc
            .entry("route")
            .or_insert_with(|| Item::ArrayOfTables(ArrayOfTables::new()));
        if let Some(list) = list.as_array_of_tables_mut() {
            list.push(table);
        }
    }

    /// Adds a host to the `hosts` of the route at `index`
    pub fn add_host(&mut self, index: usize, host: &str) {
        if let Some(hosts) = self
            .route_table(index)
            .get_mut("hosts")
            .and_then(Item::as_array_mut)
        {
            hosts.push(host);
        }
    }

    /// The `[[route]]` table at `index`. Indexes come from `routes`, which
    /// were read from this document.
    fn route_table(&mut self, index: usize) -> &mut Table {
        self.doc["route"]
            .as_array_of_tables_mut()
            .and_then(|list| list.get_mut(index))
            .expect("route index from this document")
    }

    /// Makes the edits for this host. Edits that delete or insert a route
    /// go last, so the indexes of the others still match the file.
    pub fn apply(&mut self, edits: &[Edit], host: &str) {
        let (mut structural, in_place): (Vec<&Edit>, Vec<&Edit>) = edits
            .iter()
            .partition(|e| matches!(e, Edit::Delete { .. } | Edit::Insert { .. }));
        for edit in in_place {
            match edit {
                Edit::Rewrite {
                    index,
                    path,
                    persist,
                } => {
                    let table = self.route_table(*index);
                    set_keeping_decor(table, "path", Value::from(path.as_str()));
                    if *persist {
                        set_keeping_decor(table, "persist", Value::from(true));
                    } else {
                        table.remove("persist");
                    }
                }
                Edit::AddHost { index } => self.add_host(*index, host),
                Edit::RemoveHost { index } => {
                    if let Some(hosts) = self
                        .route_table(*index)
                        .get_mut("hosts")
                        .and_then(Item::as_array_mut)
                    {
                        remove_host(hosts, host);
                    }
                }
                Edit::Delete { .. } | Edit::Insert { .. } => {}
            }
        }
        structural.sort_by_key(|e| match e {
            Edit::Delete { index } => std::cmp::Reverse(*index),
            Edit::Insert { after, .. } => std::cmp::Reverse(*after),
            _ => std::cmp::Reverse(0),
        });
        for edit in structural {
            let list = self.doc["route"]
                .as_array_of_tables_mut()
                .expect("route list from this document");
            match edit {
                Edit::Delete { index } => {
                    list.remove(*index);
                }
                Edit::Insert { after, route } => {
                    let mut table = new_table(route);
                    table.set_position(list.get(*after).and_then(Table::position));
                    list.insert(after + 1, table);
                }
                _ => {}
            }
        }
    }

    pub fn text(&self) -> String {
        self.doc.to_string()
    }

    /// Writes the file through a unique temp file next to it, then renames
    /// it over the file. So: a symlinked routes file (from a dotfiles repo)
    /// stays a symlink, the file keeps its mode, two shtl commands never
    /// share a temp file, and a failed write changes nothing.
    pub fn save(&self) -> Result<(), String> {
        let failed = |e: std::io::Error| format!("Could not write {}: {e}", self.file.display());
        let target = if self.file.is_symlink() {
            std::fs::canonicalize(&self.file).map_err(failed)?
        } else {
            self.file.clone()
        };
        let dir = target.parent().unwrap_or(Path::new("/"));
        std::fs::create_dir_all(dir).map_err(failed)?;
        let mode = match std::fs::metadata(&target) {
            Ok(meta) => meta.permissions().mode(),
            Err(_) => 0o644,
        };
        let mut tmp = tempfile::Builder::new()
            .prefix(".routes.toml.")
            .tempfile_in(dir)
            .map_err(failed)?;
        tmp.write_all(self.doc.to_string().as_bytes())
            .map_err(failed)?;
        tmp.as_file()
            .set_permissions(std::fs::Permissions::from_mode(mode))
            .map_err(failed)?;
        tmp.persist(&target).map_err(|e| failed(e.error))?;
        Ok(())
    }
}

/// A route's table, after a blank line
fn new_table(route: &NewRoute) -> Table {
    let mut table = Table::new();
    table.insert("name", value(&route.name));
    table.insert("path", value(&route.path));
    if route.persist {
        table.insert("persist", value(true));
    }
    table.insert("hosts", value(route.hosts.iter().collect::<Array>()));
    table.decor_mut().set_prefix("\n");
    table
}

/// Sets a key's value, keeping the spaces and comment around the old one
fn set_keeping_decor(table: &mut Table, key: &str, new: Value) {
    match table.get_mut(key).and_then(Item::as_value_mut) {
        Some(old) => {
            let decor = old.decor().clone();
            *old = new;
            *old.decor_mut() = decor;
        }
        None => {
            table.insert(key, Item::Value(new));
        }
    }
}

/// Takes `host` out of a hosts array. When the first item goes, the next
/// one takes its place in the layout (no space after "[", or the indent of
/// a multi-line array).
fn remove_host(hosts: &mut Array, host: &str) {
    loop {
        let found = hosts
            .iter()
            .position(|v| v.as_str().is_some_and(|h| host::same(h, host)));
        let Some(i) = found else { break };
        let removed = hosts.remove(i);
        if i == 0
            && let Some(first) = hosts.get_mut(0)
        {
            first
                .decor_mut()
                .set_prefix(removed.decor().prefix().cloned().unwrap_or_default());
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn new_route(name: &str, path: &str, persist: bool, hosts: &[&str]) -> NewRoute {
        NewRoute {
            name: name.into(),
            path: path.into(),
            persist,
            hosts: hosts.iter().map(|h| h.to_string()).collect(),
        }
    }

    fn store_with(text: &str) -> (tempfile::TempDir, Store) {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("routes.toml");
        std::fs::write(&file, text).unwrap();
        let store = Store::open(&file).unwrap();
        (dir, store)
    }

    #[test]
    fn open_reads_the_routes() {
        let (_dir, store) = store_with("version = 2\n[[route]]\nname = \"a\"\npath = \"/a\"\n");
        assert_eq!(store.routes.len(), 1);
        assert_eq!(store.routes[0].name, "a");
    }

    #[test]
    fn open_with_no_file_starts_an_empty_file_without_writing_it() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("shtl").join("routes.toml");
        let store = Store::open(&file).unwrap();
        assert!(store.routes.is_empty());
        assert_eq!(store.text(), "version = 2\n");
        assert!(!file.exists());
    }

    #[test]
    fn open_rejects_a_bad_file() {
        let (dir, _) = store_with("version = 2\n");
        let file = dir.path().join("routes.toml");
        std::fs::write(&file, "version = 1\n").unwrap();
        assert!(Store::open(&file).unwrap_err().contains("version = 2"));
    }

    #[test]
    fn push_adds_the_first_route_after_a_blank_line() {
        let (_dir, mut store) = store_with("version = 2\n");
        store.push(&new_route("work", "~/work", false, &["mbp"]));
        assert_eq!(
            store.text(),
            "version = 2\n\n[[route]]\nname = \"work\"\npath = \"~/work\"\nhosts = [\"mbp\"]\n"
        );
    }

    #[test]
    fn push_keeps_comments_and_writes_persist_only_when_set() {
        let (_dir, mut store) =
            store_with("version = 2\n\n# Work\n[[route]]\nname = \"a\"\npath = \"/a\"  # main\n");
        store.push(&new_route("nas", "/Volumes/nas", true, &["midgard"]));
        assert_eq!(
            store.text(),
            "version = 2\n\n# Work\n[[route]]\nname = \"a\"\npath = \"/a\"  # main\n\n[[route]]\nname = \"nas\"\npath = \"/Volumes/nas\"\npersist = true\nhosts = [\"midgard\"]\n"
        );
    }

    #[test]
    fn add_host_extends_the_routes_hosts() {
        let (_dir, mut store) = store_with(
            "version = 2\n[[route]]\nname = \"a\"\npath = \"/a\"\n[[route]]\nname = \"b\"\npath = \"/b\"\nhosts = [\"midgard\"]\n",
        );
        store.add_host(1, "mbp");
        assert_eq!(
            store.text(),
            "version = 2\n[[route]]\nname = \"a\"\npath = \"/a\"\n[[route]]\nname = \"b\"\npath = \"/b\"\nhosts = [\"midgard\", \"mbp\"]\n"
        );
    }

    const SHARED: &str = "version = 2\n\n# Work\n[[route]]\nname = \"work\"\npath = \"/old\"  # was\nhosts = [\"mbp\", \"midgard\"]\n\n# Last\n[[route]]\nname = \"z\"\npath = \"/z\"\n";

    #[test]
    fn apply_rewrite_keeps_comments_and_drops_persist_false() {
        let (_dir, mut store) = store_with(
            "version = 2\n[[route]]\nname = \"w\"\npath = \"/old\"  # was\npersist = true\nhosts = [\"mbp\"]\n",
        );
        store.apply(
            &[Edit::Rewrite {
                index: 0,
                path: "/new".into(),
                persist: false,
            }],
            "mbp",
        );
        assert_eq!(
            store.text(),
            "version = 2\n[[route]]\nname = \"w\"\npath = \"/new\"  # was\nhosts = [\"mbp\"]\n"
        );
        store.apply(
            &[Edit::Rewrite {
                index: 0,
                path: "/new".into(),
                persist: true,
            }],
            "mbp",
        );
        assert_eq!(
            store.text(),
            "version = 2\n[[route]]\nname = \"w\"\npath = \"/new\"  # was\nhosts = [\"mbp\"]\npersist = true\n"
        );
    }

    #[test]
    fn apply_split_inserts_after_the_route_it_splits() {
        let (_dir, mut store) = store_with(SHARED);
        store.apply(
            &[
                Edit::RemoveHost { index: 0 },
                Edit::Insert {
                    after: 0,
                    route: new_route("work", "/new", false, &["MBP"]),
                },
            ],
            "MBP",
        );
        assert_eq!(
            store.text(),
            "version = 2\n\n# Work\n[[route]]\nname = \"work\"\npath = \"/old\"  # was\nhosts = [\"midgard\"]\n\n[[route]]\nname = \"work\"\npath = \"/new\"\nhosts = [\"MBP\"]\n\n# Last\n[[route]]\nname = \"z\"\npath = \"/z\"\n"
        );
    }

    #[test]
    fn apply_remove_host_keeps_the_arrays_style() {
        let (_dir, mut store) = store_with(
            "version = 2\n[[route]]\nname = \"a\"\npath = \"/a\"\nhosts = [\"x\", \"mbp\", \"y\"]\n[[route]]\nname = \"b\"\npath = \"/b\"\nhosts = [\n  \"mbp\",\n  \"y\",\n]\n",
        );
        store.apply(
            &[Edit::RemoveHost { index: 0 }, Edit::RemoveHost { index: 1 }],
            "mbp",
        );
        assert_eq!(
            store.text(),
            "version = 2\n[[route]]\nname = \"a\"\npath = \"/a\"\nhosts = [\"x\", \"y\"]\n[[route]]\nname = \"b\"\npath = \"/b\"\nhosts = [\n  \"y\",\n]\n"
        );
    }

    #[test]
    fn apply_join_and_delete() {
        let (_dir, mut store) = store_with(
            "version = 2\n\n# Mine\n[[route]]\nname = \"w\"\npath = \"/old\"\nhosts = [\"mbp\"]\n\n# Theirs\n[[route]]\nname = \"w\"\npath = \"/new\"\nhosts = [\"asgard\"]\n",
        );
        store.apply(
            &[Edit::Delete { index: 0 }, Edit::AddHost { index: 1 }],
            "mbp",
        );
        assert_eq!(
            store.text(),
            "version = 2\n\n# Theirs\n[[route]]\nname = \"w\"\npath = \"/new\"\nhosts = [\"asgard\", \"mbp\"]\n"
        );
    }

    #[test]
    fn save_creates_the_file_and_its_directory() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("shtl").join("routes.toml");
        let mut store = Store::open(&file).unwrap();
        store.push(&new_route("a", "/a", false, &["mbp"]));
        store.save().unwrap();
        assert_eq!(std::fs::read_to_string(&file).unwrap(), store.text());
        let mode = std::fs::metadata(&file).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o644);
    }

    #[test]
    fn save_keeps_the_files_mode() {
        let (dir, mut store) = store_with("version = 2\n");
        let file = dir.path().join("routes.toml");
        std::fs::set_permissions(&file, std::fs::Permissions::from_mode(0o640)).unwrap();
        store.push(&new_route("a", "/a", false, &["mbp"]));
        store.save().unwrap();
        let mode = std::fs::metadata(&file).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o640);
        assert!(
            std::fs::read_to_string(&file)
                .unwrap()
                .contains("name = \"a\"")
        );
    }

    #[test]
    fn save_writes_through_a_symlink_and_keeps_it() {
        let dir = tempfile::tempdir().unwrap();
        let real = dir.path().join("dotfiles").join("routes.toml");
        std::fs::create_dir_all(real.parent().unwrap()).unwrap();
        std::fs::write(&real, "version = 2\n").unwrap();
        let link = dir.path().join("routes.toml");
        std::os::unix::fs::symlink(&real, &link).unwrap();

        let mut store = Store::open(&link).unwrap();
        store.push(&new_route("a", "/a", false, &["mbp"]));
        store.save().unwrap();

        assert!(
            std::fs::symlink_metadata(&link)
                .unwrap()
                .file_type()
                .is_symlink()
        );
        assert!(
            std::fs::read_to_string(&real)
                .unwrap()
                .contains("name = \"a\"")
        );
        let leftovers = std::fs::read_dir(real.parent().unwrap()).unwrap().count();
        assert_eq!(leftovers, 1, "temp file left behind");
    }
}
