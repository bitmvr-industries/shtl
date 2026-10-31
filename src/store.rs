//! Changes to the routes file. Each change edits only its own route in the
//! TOML document, so comments, blank lines and order stay.

use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

use toml_edit::{Array, ArrayOfTables, DocumentMut, Item, Table, value};

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
        let mut table = Table::new();
        table.insert("name", value(&route.name));
        table.insert("path", value(&route.path));
        if route.persist {
            table.insert("persist", value(true));
        }
        table.insert("hosts", value(route.hosts.iter().collect::<Array>()));
        table.decor_mut().set_prefix("\n");
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
