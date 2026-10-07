use crate::error::{IoResultExt, PxeBootError, Result};
use async_trait::async_trait;
use std::path::{Path, PathBuf};
use std::process::Stdio;
use tokio::process::Command;

/// Seam for `PxeBootService` (C33) -- lets tests inject a `FakeIsoMounter`
/// to get deterministic per-ISO mount outcomes (including partial success
/// across multiple ISOs), which the real `mount` command can't produce
/// unprivileged in CI (it always fails the same way for every ISO).
#[async_trait]
pub trait IsoMounting: Send + Sync {
    async fn mount(&self, iso_path: &Path) -> Result<PathBuf>;
    async fn unmount_all(&self) -> Result<()>;
}

/// `/proc/mounts` octal-escapes space, tab, newline, and backslash in its
/// whitespace-delimited fields (`\040` for a space, etc.) -- any path
/// built in-process (never escaped this way) must have its own fields
/// unescaped before comparison, or a mount point/backing file containing
/// one of those characters silently never matches.
fn unescape_mount_field(field: &str) -> String {
    let bytes = field.as_bytes();
    let mut result: Vec<u8> = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'\\'
            && i + 3 < bytes.len()
            && bytes[i + 1..i + 4].iter().all(|b| (b'0'..=b'7').contains(b))
        {
            let octal_str = std::str::from_utf8(&bytes[i + 1..i + 4]).unwrap();
            let value = u8::from_str_radix(octal_str, 8).unwrap_or(bytes[i]);
            result.push(value);
            i += 4;
        } else {
            result.push(bytes[i]);
            i += 1;
        }
    }
    String::from_utf8_lossy(&result).into_owned()
}


pub struct IsoMounter {
    runtime_root: PathBuf,
}

impl IsoMounter {
    pub fn new(runtime_root: PathBuf) -> Self {
        Self { runtime_root }
    }

    pub fn mount_path(&self, iso_name: &str) -> PathBuf {
        self.runtime_root.join("iso-mountpoint").join(iso_name)
    }

    /// Mount an ISO, handling existing mounts intelligently
    pub async fn mount(&self, iso_path: &Path) -> Result<PathBuf> {
        let iso_name = iso_path
            .file_name()
            .ok_or_else(|| PxeBootError::Config("Invalid ISO path".into()))?
            .to_string_lossy();

        let mount_point = self.mount_path(&iso_name);

        // Create mount point
        tokio::fs::create_dir_all(&mount_point)
            .await
            .with_path(&mount_point)?;

        // Check if already mounted
        if self.is_mounted(&mount_point).await? {
            // Verify it's the correct ISO
            if self.verify_mount(&mount_point, iso_path).await? {
                tracing::info!("ISO already correctly mounted: {}", iso_name);
                return Ok(mount_point);
            } else {
                // Wrong ISO mounted, unmount it
                tracing::warn!(
                    "Incorrect ISO mounted at {}, remounting",
                    mount_point.display()
                );
                self.unmount(&mount_point).await?;
            }
        }

        // Mount the ISO
        self.do_mount(iso_path, &mount_point).await?;

        tracing::info!(
            "Mounted ISO: {} -> {}",
            iso_name,
            mount_point.display()
        );
        Ok(mount_point)
    }

    async fn is_mounted(&self, path: &Path) -> Result<bool> {
        let output = Command::new("mountpoint")
            .arg("-q")
            .arg(path)
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .await?;

        Ok(output.success())
    }

    async fn verify_mount(&self, mount_point: &Path, expected_iso: &Path) -> Result<bool> {
        // Find which device (if any) is mounted at mount_point.
        let mounts = tokio::fs::read_to_string("/proc/mounts")
            .await
            .with_path("/proc/mounts")?;

        let mut loop_device = None;
        for line in mounts.lines() {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 2 && unescape_mount_field(parts[1]) == mount_point.to_string_lossy() {
                loop_device = Some(parts[0].to_string());
                break;
            }
        }

        let Some(loop_device) = loop_device else {
            return Ok(false);
        };

        // For a loop mount (`mount -o loop`, what `do_mount` uses, creates
        // one implicitly), /proc/mounts' source field is the loop DEVICE
        // NODE (e.g. "/dev/loop3"), never the backing file path -- so it
        // can never equal `expected_iso` by direct comparison. The real
        // backing file is exposed by the kernel at
        // /sys/block/loopN/loop/backing_file.
        let Some(loop_name) = loop_device.strip_prefix("/dev/") else {
            return Ok(false); // not a loop device at all
        };

        let backing_file_path = format!("/sys/block/{}/loop/backing_file", loop_name);
        let backing_file = match tokio::fs::read_to_string(&backing_file_path).await {
            Ok(contents) => PathBuf::from(contents.trim()),
            Err(_) => return Ok(false), // device vanished, or not a loop device
        };

        // Canonicalize both sides so relative paths / symlinks don't
        // cause a false mismatch; fall back to the raw path if
        // canonicalization fails (e.g. the file was removed underneath
        // us) rather than erroring the whole check out.
        let canonical_backing = tokio::fs::canonicalize(&backing_file)
            .await
            .unwrap_or(backing_file);
        let canonical_expected = tokio::fs::canonicalize(expected_iso)
            .await
            .unwrap_or_else(|_| expected_iso.to_path_buf());

        Ok(canonical_backing == canonical_expected)
    }

    async fn do_mount(&self, iso_path: &Path, mount_point: &Path) -> Result<()> {
        let output = Command::new("mount")
            .arg("-t")
            .arg("iso9660")
            .arg("-o")
            .arg("loop,ro")
            .arg(iso_path)
            .arg(mount_point)
            .output()
            .await?;

        if !output.status.success() {
            // `.output()` (vs the previous `.status()`) captures stderr
            // instead of letting it inherit straight through to this
            // process's own stderr -- without this, the ONLY place
            // `mount`'s actual reason (e.g. "mount: ...: Permission
            // denied.") ever surfaced was the systemd journal, invisible
            // to anything consuming `PxeBootError` programmatically
            // (e.g. the `status` CLI subcommand). Re-emit via
            // `tracing::error!` too, so journal-based debugging doesn't
            // regress.
            let stderr = String::from_utf8_lossy(&output.stderr);
            tracing::error!(
                "mount command failed for {}: {}",
                iso_path.display(),
                stderr.trim()
            );
            return Err(PxeBootError::MountFailed {
                path: iso_path.to_path_buf(),
                reason: format!(
                    "mount command exited with {}: {}",
                    output.status,
                    stderr.trim()
                ),
            });
        }

        Ok(())
    }

    async fn unmount(&self, mount_point: &Path) -> Result<()> {
        let output = Command::new("umount").arg(mount_point).output().await?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            tracing::error!(
                "umount command failed for {}: {}",
                mount_point.display(),
                stderr.trim()
            );
            return Err(PxeBootError::MountFailed {
                path: mount_point.to_path_buf(),
                reason: format!(
                    "umount command exited with {}: {}",
                    output.status,
                    stderr.trim()
                ),
            });
        }

        Ok(())
    }

    /// Unmount all ISOs (cleanup)
    pub async fn unmount_all(&self) -> Result<()> {
        let mount_root = self.runtime_root.join("iso-mountpoint");

        if !mount_root.exists() {
            return Ok(());
        }

        let mut entries = tokio::fs::read_dir(&mount_root)
            .await
            .with_path(&mount_root)?;

        while let Some(entry) = entries.next_entry().await? {
            if self.is_mounted(&entry.path()).await? {
                tracing::info!("Unmounting: {}", entry.path().display());
                // One stuck/busy mount must not abort cleanup for every
                // other ISO's mount point -- same skip+warn isolation
                // used throughout `PxeBootService::prepare()`. Verified
                // end-to-end in the pxe-boot E2E test (see
                // tests/pxe-boot/default.nix).
                if let Err(e) = self.unmount(&entry.path()).await {
                    tracing::warn!(
                        "Failed to unmount {}: {}. Skipping, will retry on next run.",
                        entry.path().display(),
                        e
                    );
                }
            }
        }

        Ok(())
    }
}

#[async_trait]
impl IsoMounting for IsoMounter {
    async fn mount(&self, iso_path: &Path) -> Result<PathBuf> {
        IsoMounter::mount(self, iso_path).await
    }

    async fn unmount_all(&self) -> Result<()> {
        IsoMounter::unmount_all(self).await
    }
}

/// Test double for [`IsoMounting`] -- `pub` so `lib.rs`'s test module can
/// use it (see the note on `FakeIsoDiscovery` in iso/discovery.rs).
/// Keyed by ISO file name (not the full path), since that's the only part
/// callers can predict without depending on a real discovered path.
#[cfg(test)]
pub struct FakeIsoMounter {
    successes: std::collections::HashMap<String, PathBuf>,
    failures: std::collections::HashMap<String, String>,
}

#[cfg(test)]
impl Default for FakeIsoMounter {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
impl FakeIsoMounter {
    pub fn new() -> Self {
        Self {
            successes: Default::default(),
            failures: Default::default(),
        }
    }

    pub fn succeeding_for(mut self, iso_file_name: &str, mount_path: PathBuf) -> Self {
        self.successes.insert(iso_file_name.to_string(), mount_path);
        self
    }

    pub fn failing_for(mut self, iso_file_name: &str, reason: &str) -> Self {
        self.failures
            .insert(iso_file_name.to_string(), reason.to_string());
        self
    }
}

#[cfg(test)]
#[async_trait]
impl IsoMounting for FakeIsoMounter {
    async fn mount(&self, iso_path: &Path) -> Result<PathBuf> {
        let name = iso_path
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_default();

        if let Some(reason) = self.failures.get(&name) {
            return Err(PxeBootError::MountFailed {
                path: iso_path.to_path_buf(),
                reason: reason.clone(),
            });
        }
        if let Some(path) = self.successes.get(&name) {
            return Ok(path.clone());
        }
        panic!("FakeIsoMounter: no configured result for '{name}' -- call .succeeding_for() or .failing_for() in the test setup");
    }

    async fn unmount_all(&self) -> Result<()> {
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn passes_through_a_clean_field_unchanged() {
        assert_eq!(unescape_mount_field("/run/pxe-boot/iso-mountpoint/foo.iso"), "/run/pxe-boot/iso-mountpoint/foo.iso");
    }

    #[test]
    fn unescapes_octal_space() {
        // /proc/mounts escapes a literal space as \040.
        assert_eq!(
            unescape_mount_field("/run/pxe-boot/iso-mountpoint/Ubuntu\\040Server.iso"),
            "/run/pxe-boot/iso-mountpoint/Ubuntu Server.iso"
        );
    }

    #[test]
    fn unescapes_octal_tab_newline_and_backslash() {
        assert_eq!(unescape_mount_field("a\\011b"), "a\tb");
        assert_eq!(unescape_mount_field("a\\012b"), "a\nb");
        assert_eq!(unescape_mount_field("a\\134b"), "a\\b");
    }

    #[test]
    fn leaves_a_trailing_backslash_with_no_room_for_an_escape_untouched() {
        // Not a valid 3-digit octal escape (not enough bytes remain) --
        // must not panic or silently drop the backslash.
        assert_eq!(unescape_mount_field("foo\\"), "foo\\");
    }

    #[test]
    fn leaves_a_non_octal_backslash_sequence_untouched() {
        // "\04x" -- "x" is not an octal digit, so this isn't a valid
        // escape sequence at all; pass it through byte-for-byte rather
        // than guessing.
        assert_eq!(unescape_mount_field("foo\\04xbar"), "foo\\04xbar");
    }
}
