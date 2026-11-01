//! `shtl setup` and `shtl unsetup`: the shell function's lines in the rc
//! file of the user's shell.

use std::io::{IsTerminal, Write};
use std::path::{Path, PathBuf};

use crate::paths;

/// The lines setup adds. The marker lets unsetup find them.
pub const MARKER: &str = "# shtl: https://github.com/bitmvr-industries/shtl";
/// Placeholders for the functions in `shtl init`. Each one loads the real
/// functions on its first call, then passes the call on. The rc file can't run
/// shtl itself: PATH may change after it, e.g. the stock Ubuntu ~/.profile reads
/// ~/.bashrc before it adds ~/.local/bin. While shtl isn't installed, the `shtl`
/// call reports that once, and the `_shtl` placeholder stays so Tab is quiet.
const PLACEHOLDERS: &str = r#"shtl() { unset -f shtl; eval "$(command shtl init 2>/dev/null)"; shtl "$@"; }; _shtl() { local s; s="$(command shtl init 2>/dev/null)" || return; unset -f _shtl; eval "$s"; _shtl "$@"; }"#;

/// The line after the marker: the placeholders, and completion for this shell
fn init_line(shell: &str) -> String {
    let completion = if shell.ends_with("/zsh") {
        "if (( $+functions[compdef] )); then compdef _shtl shtl; fi"
    } else {
        "complete -F _shtl shtl"
    };
    format!("{PLACEHOLDERS}; {completion}")
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Os {
    MacOs,
    Other,
}

impl Os {
    pub fn this() -> Os {
        if cfg!(target_os = "macos") {
            Os::MacOs
        } else {
            Os::Other
        }
    }
}

/// The rc files that the login shell reads at startup and that setup can
/// use. The last one is the file setup edits. Empty for shells other than
/// bash and zsh.
pub fn rc_files(shell: &str, os: Os, home: &Path, zdotdir: Option<&str>) -> Vec<PathBuf> {
    if shell.ends_with("/zsh") {
        return vec![zshrc(home, zdotdir)];
    }
    if !shell.ends_with("/bash") {
        return vec![];
    }
    let bashrc = home.join(".bashrc");
    if os != Os::MacOs {
        return vec![bashrc];
    }
    // macOS terminals open login shells, which don't read ~/.bashrc unless
    // the login file sources it. bash reads the first of these that exists.
    // With none, ~/.bash_profile: making it when ~/.profile exists would
    // stop bash from reading ~/.profile.
    let login = [".bash_profile", ".bash_login", ".profile"]
        .iter()
        .map(|f| home.join(f))
        .find(|f| f.exists())
        .unwrap_or_else(|| home.join(".bash_profile"));
    let sources = std::fs::read_to_string(&login).is_ok_and(|text| sources_bashrc(&text));
    if sources {
        vec![login, bashrc]
    } else {
        vec![login]
    }
}

fn zshrc(home: &Path, zdotdir: Option<&str>) -> PathBuf {
    match zdotdir {
        Some(dir) if !dir.is_empty() => Path::new(dir).join(".zshrc"),
        _ => home.join(".zshrc"),
    }
}

/// Every rc file unsetup checks, wherever setup put the lines before
pub fn all_rc_files(shell: &str, home: &Path, zdotdir: Option<&str>) -> Vec<PathBuf> {
    if shell.ends_with("/zsh") {
        vec![zshrc(home, zdotdir)]
    } else if shell.ends_with("/bash") {
        [".bash_profile", ".bash_login", ".profile", ".bashrc"]
            .iter()
            .map(|f| home.join(f))
            .collect()
    } else {
        vec![]
    }
}

/// True when the text sources ~/.bashrc on a line that isn't a comment,
/// e.g. `[ -f ~/.bashrc ] && . ~/.bashrc` or `source "$HOME/.bashrc"`
pub fn sources_bashrc(text: &str) -> bool {
    let pattern = regex_lite::Regex::new(
        r#"^[^#]*(?:^|[\s;&|{(])(?:source|\.)\s+["']?(?:~|\$HOME|\$\{HOME\})["']?/\.bashrc(?:["'\s;&|)]|$)"#,
    )
    .expect("valid pattern");
    text.lines().any(|line| pattern.is_match(line))
}

/// The text without the marker, the line after it, and the blank line that
/// setup put before them
pub fn remove_rc_lines(text: &str) -> String {
    let lines: Vec<&str> = text.lines().collect();
    let mut skip = vec![false; lines.len()];
    for i in 0..lines.len() {
        if lines[i] == MARKER && lines.get(i + 1).is_some_and(|l| l.contains("shtl init")) {
            skip[i] = true;
            skip[i + 1] = true;
            if i > 0 && lines[i - 1].is_empty() {
                skip[i - 1] = true;
            }
        }
    }
    lines
        .iter()
        .zip(skip)
        .filter(|(_, skip)| !skip)
        .map(|(line, _)| format!("{line}\n"))
        .collect()
}

fn env(name: &str) -> String {
    std::env::var(name).unwrap_or_default()
}

/// A path as the user knows it: ~/... under the home directory
fn shown(path: &Path) -> String {
    paths::contract(&path.display().to_string(), &env("HOME"))
}

/// Asks a yes/no question on stderr. No without a terminal, so scripts
/// never edit files.
fn confirm(question: &str) -> bool {
    if !std::io::stdin().is_terminal() {
        return false;
    }
    eprint!("{question} [y/N] ");
    let _ = std::io::stderr().flush();
    let mut reply = String::new();
    if std::io::stdin().read_line(&mut reply).is_err() {
        return false;
    }
    matches!(reply.trim().to_lowercase().as_str(), "y" | "yes")
}

fn print_rc_lines(file: &Path) {
    println!("\n    {MARKER}\n    {}\n", init_line(&env("SHELL")));
    if let Ok(target) = std::fs::read_link(file) {
        println!(
            "Note: {} is a symlink to {}. The change will be made in that file.",
            shown(file),
            target.display()
        );
    }
}

/// Offers to add the shell function to the rc file of the user's shell
pub fn setup() -> Result<(), String> {
    let shell = env("SHELL");
    let home = env("HOME");
    let zdotdir = std::env::var("ZDOTDIR").ok();
    let files = rc_files(&shell, Os::this(), Path::new(&home), zdotdir.as_deref());
    let Some(rc) = files.last() else {
        println!(
            "shtl's shell function supports bash and zsh. Without it, use: cd \"$(shtl path ROUTE_NAME)\""
        );
        return Ok(());
    };
    for file in &files {
        if std::fs::read_to_string(file).is_ok_and(|text| text.contains("shtl init")) {
            println!("Shell integration already set up in {}", shown(file));
            return Ok(());
        }
    }
    let rc_shown = shown(rc);
    println!("shtl needs these lines in {rc_shown} to change directories and tab-complete routes.");
    if files.len() > 1 {
        println!(
            "{} sources ~/.bashrc, so the lines go in ~/.bashrc.",
            shown(&files[0])
        );
    }
    print_rc_lines(rc);

    if confirm(&format!("Append them to the end of {rc_shown}?")) {
        let failed = |e: std::io::Error| format!("Could not write {rc_shown}: {e}");
        let not_empty = std::fs::metadata(rc).is_ok_and(|m| m.len() > 0);
        let mut file = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(rc)
            .map_err(failed)?;
        // Separate from existing content with a blank line
        let blank = if not_empty { "\n" } else { "" };
        write!(file, "{blank}{MARKER}\n{}\n", init_line(&shell)).map_err(failed)?;
        println!("Added. Open a new terminal, or run: source {rc_shown}");
    } else if shell.ends_with("/zsh") {
        println!("Skipped. To set it up yourself, add those lines to the end of {rc_shown}");
        println!("(after compinit, so tab completion works), then open a new terminal.");
    } else {
        println!(
            "Skipped. To set it up yourself, add those lines to the end of {rc_shown}, then open a new terminal."
        );
    }
    Ok(())
}

/// Offers to remove the lines setup added, from each rc file that has them.
/// Writes in place, so symlinks and modes stay.
pub fn unsetup() -> Result<(), String> {
    let home = env("HOME");
    let zdotdir = std::env::var("ZDOTDIR").ok();
    let mut found = false;
    for file in all_rc_files(&env("SHELL"), Path::new(&home), zdotdir.as_deref()) {
        let Ok(text) = std::fs::read_to_string(&file) else {
            continue;
        };
        let file_shown = shown(&file);
        if text.lines().any(|line| line == MARKER) {
            found = true;
            println!("{file_shown} has shtl's shell integration lines.");
            print_rc_lines(&file);
            if confirm(&format!("Remove them from {file_shown}?")) {
                std::fs::write(&file, remove_rc_lines(&text))
                    .map_err(|e| format!("Could not write {file_shown}: {e}"))?;
                println!("Removed.");
            } else {
                println!(
                    "Kept. The line is safe while shtl isn't installed: it runs shtl only when you use it."
                );
            }
        } else if text.contains("shtl init") {
            found = true;
            println!(
                "{file_shown} runs 'shtl init'. setup didn't add that line, so remove it yourself."
            );
        }
    }
    if !found {
        println!("No shtl lines in your rc files");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn home() -> tempfile::TempDir {
        tempfile::tempdir().unwrap()
    }

    fn write(home: &Path, file: &str, text: &str) {
        std::fs::write(home.join(file), text).unwrap();
    }

    fn names(home: &Path, files: Vec<PathBuf>) -> Vec<String> {
        files
            .iter()
            .map(|f| f.strip_prefix(home).unwrap().display().to_string())
            .collect()
    }

    #[test]
    fn zsh_uses_zshrc_in_zdotdir_or_home() {
        let h = home();
        let p = h.path();
        assert_eq!(
            names(p, rc_files("/bin/zsh", Os::MacOs, p, None)),
            [".zshrc"]
        );
        assert_eq!(
            names(p, rc_files("/usr/bin/zsh", Os::Other, p, Some(""))),
            [".zshrc"]
        );
        let zdot = p.join("z").display().to_string();
        assert_eq!(
            names(p, rc_files("/bin/zsh", Os::Other, p, Some(&zdot))),
            ["z/.zshrc"]
        );
    }

    #[test]
    fn bash_on_linux_uses_bashrc() {
        let h = home();
        let p = h.path();
        write(p, ".bash_profile", "export A=1\n");
        assert_eq!(
            names(p, rc_files("/bin/bash", Os::Other, p, None)),
            [".bashrc"]
        );
    }

    #[test]
    fn bash_on_macos_uses_the_login_file_bash_reads_first() {
        let h = home();
        let p = h.path();
        assert_eq!(
            names(p, rc_files("/bin/bash", Os::MacOs, p, None)),
            [".bash_profile"]
        );
        write(p, ".profile", "export B=1\n");
        assert_eq!(
            names(p, rc_files("/bin/bash", Os::MacOs, p, None)),
            [".profile"]
        );
        write(p, ".bash_login", "export A=1\n");
        assert_eq!(
            names(p, rc_files("/opt/homebrew/bin/bash", Os::MacOs, p, None)),
            [".bash_login"]
        );
    }

    #[test]
    fn bash_on_macos_uses_bashrc_when_the_login_file_sources_it() {
        let h = home();
        let p = h.path();
        write(p, ".bash_profile", "export A=1\nsource ~/.bashrc\n");
        assert_eq!(
            names(p, rc_files("/bin/bash", Os::MacOs, p, None)),
            [".bash_profile", ".bashrc"]
        );
    }

    #[test]
    fn other_shells_have_no_rc_file() {
        let h = home();
        assert!(rc_files("/usr/local/bin/fish", Os::MacOs, h.path(), None).is_empty());
        assert!(all_rc_files("/usr/local/bin/fish", h.path(), None).is_empty());
    }

    #[test]
    fn unsetup_checks_every_bash_rc_file() {
        let h = home();
        let p = h.path();
        assert_eq!(
            names(p, all_rc_files("/bin/bash", p, None)),
            [".bash_profile", ".bash_login", ".profile", ".bashrc"]
        );
        assert_eq!(names(p, all_rc_files("/bin/zsh", p, None)), [".zshrc"]);
    }

    #[test]
    fn finds_the_ways_to_source_bashrc() {
        for line in [
            "source ~/.bashrc",
            ". ~/.bashrc",
            "[ -f ~/.bashrc ] && . ~/.bashrc",
            r#"[[ -r "$HOME/.bashrc" ]] && source "$HOME/.bashrc""#,
            r#"if [ -f "${HOME}/.bashrc" ]; then . "${HOME}/.bashrc"; fi"#,
            "    source $HOME/.bashrc",
            "if [ -n \"$BASH_VERSION\" ]; then\n    if [ -f \"$HOME/.bashrc\" ]; then\n\t. \"$HOME/.bashrc\"\n    fi\nfi",
        ] {
            assert!(sources_bashrc(&format!("export A=1\n{line}\n")), "{line}");
        }
    }

    #[test]
    fn ignores_comments_and_other_files() {
        for text in [
            "# source ~/.bashrc\n",
            "  # . ~/.bashrc\n",
            "source ~/.bashrc.d/x\n",
            "source ~/.bashrc_old\n",
            "cat ~/.bashrc\n",
            "mysource ~/.bashrc\n",
        ] {
            assert!(!sources_bashrc(text), "{text}");
        }
    }

    #[test]
    fn remove_rc_lines_takes_the_lines_and_the_blank_line_before() {
        let line = init_line("/bin/bash");
        let text = format!("export B=1\n\n{MARKER}\n{line}\nexport C=1\n");
        assert_eq!(remove_rc_lines(&text), "export B=1\nexport C=1\n");
        let text = format!("{MARKER}\n{line}\n");
        assert_eq!(remove_rc_lines(&text), "");
    }

    #[test]
    fn remove_rc_lines_keeps_a_marker_without_the_init_line() {
        let text = format!("{MARKER}\nsomething else\n");
        assert_eq!(remove_rc_lines(&text), text);
    }
}
