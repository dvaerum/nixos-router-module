//! Best-effort architecture detection from an ISO's own filename.
//!
//! Real-world Ubuntu/RHEL/Rocky/Alma netboot images universally encode
//! their target architecture in the filename itself (e.g.
//! `ubuntu-24.04-live-server-amd64.iso`, `rhel-9.6-x86_64-dvd.iso`) --
//! this is far more reliable than parsing a kernel image's own binary
//! format, which differs by architecture (x86 bzImage vs aarch64 Image)
//! and by compression, and the mounted ISO's directory layout gives no
//! architecture signal at all for either distro family. NixOS has its
//! own, more authoritative source (bootspec's `system` field -- see
//! `distro::nixos::architecture_from_system`) and does not use this.

/// Normalizes to the Linux/Nix CPU-name convention (e.g. "x86_64",
/// "aarch64") -- both "amd64" (Debian/Ubuntu's naming) and "x86_64"
/// (RHEL's naming) collapse to "x86_64". NOT the same as GRUB's own
/// `$grub_cpu` convention -- see `to_grub_cpu` below for that mapping,
/// confirmed to differ for at least aarch64.
const MARKERS: &[(&str, &str)] = &[
    ("x86_64", "x86_64"),
    ("amd64", "x86_64"),
    ("aarch64", "aarch64"),
    ("arm64", "aarch64"),
    ("ppc64le", "ppc64le"),
    ("s390x", "s390x"),
    ("i686", "i686"),
    ("i386", "i686"),
];

pub fn detect_architecture_from_file_name(file_name: &str) -> Option<String> {
    let lower = file_name.to_lowercase();
    MARKERS
        .iter()
        .find(|(marker, _)| lower.contains(marker))
        .map(|(_, normalized)| normalized.to_string())
}

/// Maps a Linux/Nix architecture string (as produced by
/// `detect_architecture_from_file_name`/`nixos::architecture_from_system`)
/// to GRUB's own `$grub_cpu` value, for A6's conditional-entry filtering.
///
/// NOT a 1:1 passthrough -- confirmed directly against GRUB's own build
/// system (`configure.ac`): `grub_env_set("grub_cpu", GRUB_TARGET_CPU)`
/// (grub-core/normal/main.c), and `configure.ac`'s `target_cpu` case
/// statement normalizes `aarch64*` to `arm64` (while `amd64`/`x86_64`
/// both normalize to `x86_64`, matching the Linux/Nix string already).
/// Returns `None` for an architecture with no known GRUB mapping --
/// callers should fail OPEN (show the entry unfiltered) in that case,
/// same as an undetected architecture.
pub fn to_grub_cpu(architecture: &str) -> Option<&'static str> {
    match architecture {
        "x86_64" => Some("x86_64"),
        "aarch64" => Some("arm64"),
        "i686" => Some("i386"),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_amd64_as_x86_64() {
        assert_eq!(
            detect_architecture_from_file_name("ubuntu-24.04-live-server-amd64.iso").as_deref(),
            Some("x86_64")
        );
    }

    #[test]
    fn detects_x86_64_literally() {
        assert_eq!(
            detect_architecture_from_file_name("rhel-9.6-x86_64-dvd.iso").as_deref(),
            Some("x86_64")
        );
    }

    #[test]
    fn detects_arm64_as_aarch64() {
        assert_eq!(
            detect_architecture_from_file_name("ubuntu-24.04-live-server-arm64.iso").as_deref(),
            Some("aarch64")
        );
    }

    #[test]
    fn detects_aarch64_literally() {
        assert_eq!(
            detect_architecture_from_file_name("rhel-9.6-aarch64-dvd.iso").as_deref(),
            Some("aarch64")
        );
    }

    #[test]
    fn is_case_insensitive() {
        assert_eq!(
            detect_architecture_from_file_name("RHEL-9.6-X86_64-DVD.ISO").as_deref(),
            Some("x86_64")
        );
    }

    #[test]
    fn returns_none_when_no_known_marker_present() {
        assert_eq!(
            detect_architecture_from_file_name("mystery-distro.iso"),
            None
        );
    }

    #[test]
    fn to_grub_cpu_maps_aarch64_to_arm64_not_aarch64() {
        // The one GRUB really does NOT use the Linux/Nix string verbatim
        // for -- confirmed against GRUB's own configure.ac
        // (`aarch64*) target_cpu=arm64 ;;`). Getting this wrong would
        // make A6's filtering hide every aarch64 ISO from aarch64
        // clients themselves, the exact opposite of its purpose.
        assert_eq!(to_grub_cpu("aarch64"), Some("arm64"));
    }

    #[test]
    fn to_grub_cpu_maps_x86_64_unchanged() {
        assert_eq!(to_grub_cpu("x86_64"), Some("x86_64"));
    }

    #[test]
    fn to_grub_cpu_maps_i686_to_i386() {
        assert_eq!(to_grub_cpu("i686"), Some("i386"));
    }

    #[test]
    fn to_grub_cpu_returns_none_for_unmapped_architecture() {
        assert_eq!(to_grub_cpu("ppc64le"), None);
    }
}
