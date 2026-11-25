//! What `refresh` needs to remember between runs: the identity of each ISO
//! file as it was when mounted, so an in-place change is told apart from an
//! untouched ISO whose mount (and NFS export) must not be disturbed.

use crate::error::{IoResultExt, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};

/// Cheap identity of an ISO file. `ino` is what catches a store-built ISO
/// being swapped for another build (store files all carry the same mtime).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Fingerprint {
    pub dev: u64,
    pub ino: u64,
    pub size: u64,
    pub mtime_sec: i64,
    pub mtime_nsec: i64,
}

impl Fingerprint {
    /// Follows symlinks: the ISO folders hold links into the Nix store.
    pub async fn of(path: &Path) -> Result<Self> {
        let meta = tokio::fs::metadata(path).await.with_path(path)?;
        Ok(Self {
            dev: meta.dev(),
            ino: meta.ino(),
            size: meta.size(),
            mtime_sec: meta.mtime(),
            mtime_nsec: meta.mtime_nsec(),
        })
    }
}

/// Fingerprints by ISO file name, kept next to the mounts in the runtime
/// root (a tmpfs, so it vanishes together with the mounts it describes).
pub struct IsoState {
    path: PathBuf,
}

impl IsoState {
    pub fn new(runtime_root: &Path) -> Self {
        Self {
            path: runtime_root.join(".iso-state.json"),
        }
    }

    /// An unreadable or corrupt file reads as empty: every mounted ISO then
    /// counts as changed and is remounted, which is the safe direction.
    pub async fn load(&self) -> HashMap<String, Fingerprint> {
        let text = match tokio::fs::read_to_string(&self.path).await {
            Ok(text) => text,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return HashMap::new(),
            Err(e) => {
                tracing::warn!(
                    "Cannot read {}: {}. Treating every mounted ISO as changed.",
                    self.path.display(),
                    e
                );
                return HashMap::new();
            }
        };
        serde_json::from_str(&text).unwrap_or_else(|e| {
            tracing::warn!(
                "Corrupt {}: {}. Treating every mounted ISO as changed.",
                self.path.display(),
                e
            );
            HashMap::new()
        })
    }

    pub async fn save(&self, state: &HashMap<String, Fingerprint>) -> Result<()> {
        let tmp = self.path.with_extension("json.tmp");
        tokio::fs::write(&tmp, serde_json::to_vec(state)?)
            .await
            .with_path(&tmp)?;
        tokio::fs::rename(&tmp, &self.path)
            .await
            .with_path(&self.path)
    }

    pub async fn clear(&self) -> Result<()> {
        match tokio::fs::remove_file(&self.path).await {
            Ok(()) => Ok(()),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(e) => Err(e).with_path(&self.path),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn fingerprint_changes_when_the_file_content_length_changes() {
        let dir = tempfile::tempdir().unwrap();
        let f = dir.path().join("a.iso");
        std::fs::write(&f, b"one").unwrap();
        let before = Fingerprint::of(&f).await.unwrap();
        std::fs::write(&f, b"three").unwrap();
        assert_ne!(before, Fingerprint::of(&f).await.unwrap());
    }

    #[tokio::test]
    async fn fingerprint_changes_when_the_file_is_replaced_by_another() {
        let dir = tempfile::tempdir().unwrap();
        let f = dir.path().join("a.iso");
        std::fs::write(&f, b"same").unwrap();
        let before = Fingerprint::of(&f).await.unwrap();
        let other = dir.path().join("b.iso");
        std::fs::write(&other, b"same").unwrap();
        std::fs::rename(&other, &f).unwrap();
        assert_ne!(before, Fingerprint::of(&f).await.unwrap());
    }

    #[tokio::test]
    async fn state_round_trips_and_clears() {
        let dir = tempfile::tempdir().unwrap();
        let f = dir.path().join("a.iso");
        std::fs::write(&f, b"x").unwrap();
        let state = IsoState::new(dir.path());
        let mut map = HashMap::new();
        map.insert("a.iso".to_string(), Fingerprint::of(&f).await.unwrap());
        state.save(&map).await.unwrap();
        assert_eq!(state.load().await, map);
        state.clear().await.unwrap();
        assert!(state.load().await.is_empty());
        state.clear().await.unwrap();
    }

    #[tokio::test]
    async fn a_corrupt_state_file_reads_as_empty() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join(".iso-state.json"), "{not json").unwrap();
        assert!(IsoState::new(dir.path()).load().await.is_empty());
    }
}
