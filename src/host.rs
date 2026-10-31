//! This machine's host name, the way routes name it in `hosts`.

/// The name before the first ".", as `hostname -s` prints it.
pub fn short(name: &str) -> &str {
    name.split('.').next().unwrap_or(name)
}

/// Host names are not case-sensitive.
pub fn same(a: &str, b: &str) -> bool {
    a.eq_ignore_ascii_case(b)
}

/// This machine's name, short form. macOS: the LocalHostName from System
/// Settings → Sharing (as `scutil --get LocalHostName` prints it), which
/// the network can't change. Other systems: the kernel host name.
pub fn this_host() -> String {
    let name = local_host_name()
        .unwrap_or_else(|| gethostname::gethostname().to_string_lossy().into_owned());
    short(&name).to_string()
}

#[cfg(target_os = "macos")]
fn local_host_name() -> Option<String> {
    use core_foundation::base::TCFType;
    use core_foundation::string::CFString;
    use system_configuration_sys::dynamic_store_copy_specific::SCDynamicStoreCopyLocalHostName;

    // SAFETY: a null store asks SystemConfiguration for a temporary session.
    // The result is null, or a CFString that we own (the Copy rule).
    unsafe {
        let name = SCDynamicStoreCopyLocalHostName(std::ptr::null());
        if name.is_null() {
            return None;
        }
        let name = CFString::wrap_under_create_rule(name).to_string();
        (!name.is_empty()).then_some(name)
    }
}

#[cfg(not(target_os = "macos"))]
fn local_host_name() -> Option<String> {
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn this_host_is_a_short_name() {
        let host = this_host();
        assert!(!host.is_empty());
        assert!(!host.contains('.'), "{host}");
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn this_host_on_macos_is_the_local_host_name() {
        let out = std::process::Command::new("scutil")
            .args(["--get", "LocalHostName"])
            .output()
            .unwrap();
        assert_eq!(this_host(), String::from_utf8(out.stdout).unwrap().trim());
    }

    #[test]
    fn short_cuts_at_the_first_dot() {
        assert_eq!(short("midgard"), "midgard");
        assert_eq!(short("midgard.lan"), "midgard");
        assert_eq!(short("Jesses-MBP.local.example"), "Jesses-MBP");
    }

    #[test]
    fn same_ignores_case() {
        assert!(same("Midgard", "midgard"));
        assert!(!same("midgard", "midgard2"));
    }
}
