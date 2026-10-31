//! A throwaway HOME and config dir for each test, never your real routes.
#![allow(dead_code)]

use std::path::{Path, PathBuf};

use assert_cmd::Command;

pub struct Env {
    _dir: tempfile::TempDir,
    /// A real directory for routes to point at; the default working dir
    pub root: PathBuf,
    pub home: PathBuf,
    pub config: PathBuf,
    pub cwd: PathBuf,
}

/// This machine's host name, as shtl reads it
pub fn host() -> String {
    shtl::host::this_host()
}

impl Env {
    pub fn new() -> Env {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path().join("root");
        let home = dir.path().join("home");
        let config = dir.path().join("config");
        for d in [&root, &home, &config] {
            std::fs::create_dir_all(d).unwrap();
        }
        Env {
            cwd: root.clone(),
            _dir: dir,
            root,
            home,
            config,
        }
    }

    pub fn routes_file(&self) -> PathBuf {
        self.config.join("shtl").join("routes.toml")
    }

    pub fn write_routes(&self, text: &str) {
        std::fs::create_dir_all(self.config.join("shtl")).unwrap();
        std::fs::write(self.routes_file(), text).unwrap();
    }

    /// Makes a directory under root and returns its path
    pub fn dir(&self, rel: &str) -> PathBuf {
        let path = self.root.join(rel);
        std::fs::create_dir_all(&path).unwrap();
        path
    }

    pub fn cd(&mut self, dir: &Path) {
        self.cwd = dir.to_path_buf();
    }

    /// shtl run in cwd. PWD is set like a shell sets it, so a temp dir
    /// behind a symlink (macOS /var → /private/var) keeps its typed path.
    pub fn shtl(&self) -> Command {
        let mut cmd = Command::cargo_bin("shtl").unwrap();
        cmd.current_dir(&self.cwd)
            .env("PWD", &self.cwd)
            .env("HOME", &self.home)
            .env("XDG_CONFIG_HOME", &self.config);
        cmd
    }
}

/// stdout and stderr of a run, and its exit code
pub fn run(mut cmd: Command) -> (String, String, i32) {
    let out = cmd.output().unwrap();
    (
        String::from_utf8(out.stdout).unwrap(),
        String::from_utf8(out.stderr).unwrap(),
        out.status.code().unwrap(),
    )
}
