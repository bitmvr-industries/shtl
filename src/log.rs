//! Messages on stderr in the 1.x format: `shtl [LEVEL] message`, with the
//! bracketed level padded to 7 columns so the messages line up.

pub fn format(level: &str, msg: &str) -> String {
    format!("shtl {:<7} {msg}", format!("[{level}]"))
}

pub fn error(msg: &str) {
    eprintln!("{}", format("ERROR", msg));
}

pub fn warn(msg: &str) {
    eprintln!("{}", format("WARN", msg));
}

pub fn info(msg: &str) {
    eprintln!("{}", format("INFO", msg));
}

#[cfg(test)]
mod tests {
    use super::format;

    #[test]
    fn pads_short_levels_so_messages_line_up() {
        assert_eq!(format("INFO", "hi"), "shtl [INFO]  hi");
        assert_eq!(format("ERROR", "hi"), "shtl [ERROR] hi");
        assert_eq!(format("WARN", "hi"), "shtl [WARN]  hi");
    }

    #[test]
    fn prints_backslashes_as_given() {
        assert_eq!(format("INFO", r"a\nb"), r"shtl [INFO]  a\nb");
    }
}
