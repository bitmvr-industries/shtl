//! The interactive checklist for `shtl clean`: routes whose directories are
//! gone, all selected. It draws on stderr, so stdout stays clean.

use std::io::Write;

/// A key that the checklist uses
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Key {
    Up,
    Down,
    Toggle,
    All,
    Enter,
    Quit,
    Interrupt,
}

/// How the checklist ended
#[derive(Debug, PartialEq)]
pub enum Done {
    /// Remove the selected rows (their indexes)
    Remove(Vec<usize>),
    Cancel,
    /// Ctrl-C
    Interrupt,
}

#[derive(Debug)]
pub struct Checklist {
    pub selected: Vec<bool>,
    pub cursor: usize,
}

impl Checklist {
    pub fn new(rows: usize) -> Checklist {
        Checklist {
            selected: vec![true; rows],
            cursor: 0,
        }
    }

    /// Handles a key. Some when the checklist is done.
    pub fn key(&mut self, key: Key) -> Option<Done> {
        match key {
            Key::Up => self.cursor = self.cursor.saturating_sub(1),
            Key::Down => {
                if self.cursor + 1 < self.selected.len() {
                    self.cursor += 1;
                }
            }
            Key::Toggle => {
                if let Some(row) = self.selected.get_mut(self.cursor) {
                    *row = !*row;
                }
            }
            Key::All => {
                let all = !self.selected.iter().all(|s| *s);
                self.selected.fill(all);
            }
            Key::Enter => {
                let rows = (0..self.selected.len())
                    .filter(|i| self.selected[*i])
                    .collect();
                return Some(Done::Remove(rows));
            }
            Key::Quit => return Some(Done::Cancel),
            Key::Interrupt => return Some(Done::Interrupt),
        }
        None
    }
}

/// Raw mode and a hidden cursor, put back on every way out
struct Screen;

impl Drop for Screen {
    fn drop(&mut self) {
        let _ = write!(std::io::stderr(), "\x1b[?25h");
        let _ = crossterm::terminal::disable_raw_mode();
    }
}

/// Shows the checklist for rows of (name, path) on stderr and reads keys
/// until it is done. Needs a terminal.
pub fn run(rows: &[(String, String)]) -> std::io::Result<Done> {
    use crossterm::event::{self, Event, KeyCode, KeyEventKind, KeyModifiers};

    let mut err = std::io::stderr();
    let width = rows
        .iter()
        .map(|(name, _)| name.chars().count())
        .max()
        .unwrap_or(0);
    let mut list = Checklist::new(rows.len());

    crossterm::terminal::enable_raw_mode()?;
    let _screen = Screen;
    // Raw mode doesn't turn "\n" into a new line at the start, so: "\r\n"
    write!(
        err,
        "\x1b[?25l\r\nshtl clean — routes whose directories no longer exist\r\n\r\n"
    )?;
    write!(
        err,
        "  ↑/↓ move   space toggle   a all   enter remove   q cancel\r\n\r\n"
    )?;
    draw(&mut err, rows, &list, width)?;
    loop {
        let Event::Key(press) = event::read()? else {
            continue;
        };
        if press.kind != KeyEventKind::Press {
            continue;
        }
        let key = match press.code {
            KeyCode::Char('c') if press.modifiers.contains(KeyModifiers::CONTROL) => Key::Interrupt,
            KeyCode::Up | KeyCode::Char('k') => Key::Up,
            KeyCode::Down | KeyCode::Char('j') => Key::Down,
            KeyCode::Char(' ') => Key::Toggle,
            KeyCode::Char('a') => Key::All,
            KeyCode::Enter => Key::Enter,
            KeyCode::Char('q') => Key::Quit,
            _ => continue,
        };
        if let Some(done) = list.key(key) {
            return Ok(done);
        }
        write!(err, "\x1b[{}A", rows.len() + 2)?;
        draw(&mut err, rows, &list, width)?;
    }
}

fn draw(
    err: &mut impl Write,
    rows: &[(String, String)],
    list: &Checklist,
    width: usize,
) -> std::io::Result<()> {
    for (i, (name, path)) in rows.iter().enumerate() {
        let pointer = if i == list.cursor { ">" } else { " " };
        let mark = if list.selected[i] { "x" } else { " " };
        write!(err, "\x1b[2K{pointer} [{mark}] {name:<width$}  {path}\r\n")?;
    }
    let count = list.selected.iter().filter(|s| **s).count();
    write!(err, "\x1b[2K\r\n\x1b[2K{count} selected\r\n")?;
    err.flush()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn starts_with_every_row_selected() {
        let list = Checklist::new(3);
        assert_eq!(list.selected, [true, true, true]);
        assert_eq!(list.cursor, 0);
    }

    #[test]
    fn up_and_down_stop_at_the_ends() {
        let mut list = Checklist::new(2);
        list.key(Key::Up);
        assert_eq!(list.cursor, 0);
        list.key(Key::Down);
        list.key(Key::Down);
        assert_eq!(list.cursor, 1);
        list.key(Key::Up);
        assert_eq!(list.cursor, 0);
    }

    #[test]
    fn toggle_changes_the_row_under_the_cursor() {
        let mut list = Checklist::new(2);
        list.key(Key::Down);
        list.key(Key::Toggle);
        assert_eq!(list.selected, [true, false]);
        list.key(Key::Toggle);
        assert_eq!(list.selected, [true, true]);
    }

    #[test]
    fn all_deselects_when_all_are_selected_else_selects_all() {
        let mut list = Checklist::new(2);
        list.key(Key::All);
        assert_eq!(list.selected, [false, false]);
        list.key(Key::Toggle);
        list.key(Key::All);
        assert_eq!(list.selected, [true, true]);
    }

    #[test]
    fn enter_removes_the_selected_rows() {
        let mut list = Checklist::new(3);
        list.key(Key::Down);
        assert_eq!(list.key(Key::Toggle), None);
        assert_eq!(list.key(Key::Enter), Some(Done::Remove(vec![0, 2])));
    }

    #[test]
    fn quit_and_interrupt_end_without_removing() {
        assert_eq!(Checklist::new(1).key(Key::Quit), Some(Done::Cancel));
        assert_eq!(Checklist::new(1).key(Key::Interrupt), Some(Done::Interrupt));
    }
}
