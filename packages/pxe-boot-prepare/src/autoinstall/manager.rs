use crate::config::{DistroType, PxeBootConfig};
use crate::error::{PxeBootError, Result};
use async_trait::async_trait;
use std::collections::HashMap;
use std::path::{Path, PathBuf};

/// Seam for `PxeBootService` (C33).
#[async_trait]
pub trait AutoinstallPreparing: Send + Sync {
    async fn prepare(
        &self,
        config: &PxeBootConfig,
        distro_by_iso: &HashMap<String, DistroType>,
    ) -> Result<()>;
}

pub struct AutoinstallManager {
    runtime_root: PathBuf,
}

impl AutoinstallManager {
    pub fn new(runtime_root: PathBuf) -> Self {
        Self { runtime_root }
    }

    /// Prepare autoinstall scripts by copying them to the runtime directory.
    ///
    /// `distro_by_iso` maps an ISO file name to its detected distribution so the
    /// on-disk layout can match what each installer expects. RHEL kickstart is
    /// served verbatim under its own name; Ubuntu (cloud-init NoCloud) needs the
    /// seed served from a directory as `user-data` alongside a `meta-data` file.
    pub async fn prepare(
        &self,
        config: &PxeBootConfig,
        distro_by_iso: &HashMap<String, DistroType>,
    ) -> Result<()> {
        let autoinstall_root = self.runtime_root.join("unattented-install");

        // C34: each (iso_name, script) pair writes to its own independent
        // path -- different ISOs never share a directory, and multiple
        // scripts for the same ISO each get their own subdir (Ubuntu) or
        // file (other distros) -- so every write below can run
        // concurrently. `ensure_dir` is idempotent (`create_dir_all`), so
        // it's safe to call per-task instead of needing a separate
        // sequential pre-pass to create each `iso_script_dir` first.
        let tasks = config.autoinstall.iter().flat_map(|(iso_name, scripts)| {
            let iso_script_dir = autoinstall_root.join(iso_name);
            let is_ubuntu = matches!(distro_by_iso.get(iso_name), Some(DistroType::Ubuntu));

            scripts.iter().cloned().map(move |script| {
                let iso_script_dir = iso_script_dir.clone();
                async move {
                    Self::ensure_dir(&iso_script_dir).await?;

                    if is_ubuntu {
                        // cloud-init NoCloud requires a seed *directory* containing a
                        // file named exactly `user-data` plus a (possibly empty)
                        // `meta-data`. Give each script its own subdir so multiple
                        // seeds never collide and the GRUB `s=<dir>/` URL points at
                        // exactly this seed.
                        let seed_dir = iso_script_dir.join(&script.name);
                        Self::ensure_dir(&seed_dir).await?;

                        let user_data = seed_dir.join("user-data");
                        tracing::debug!(
                            "Installing Ubuntu NoCloud user-data: {} -> {}",
                            script.script_path.display(),
                            user_data.display()
                        );
                        Self::install_file(&script.script_path, &user_data).await?;

                        // NoCloud treats a missing meta-data as an invalid datasource,
                        // so always write one (empty is fine).
                        Self::write_fresh(&seed_dir.join("meta-data"), b"").await?;
                    } else {
                        // Other distros (e.g. RHEL kickstart): serve the script
                        // verbatim under its own name.
                        let dest = iso_script_dir.join(&script.name);
                        tracing::debug!(
                            "Copying autoinstall script: {} -> {}",
                            script.script_path.display(),
                            dest.display()
                        );
                        Self::install_file(&script.script_path, &dest).await?;
                    }

                    Ok::<(), PxeBootError>(())
                }
            })
        });

        for result in futures::future::join_all(tasks).await {
            result?;
        }

        tracing::info!("Prepared autoinstall scripts");
        Ok(())
    }

    /// Copy `src` onto `dest`, replacing any existing file.
    ///
    /// `tokio::fs::copy` preserves the source mode. The source is a /nix/store
    /// file (0444), so a prior run's destination is also 0444 — which the next
    /// overwrite cannot open for writing because this service runs without
    /// CAP_DAC_OVERRIDE. Remove the destination first so the copy is a fresh
    /// create (removal is checked against the parent directory's permissions,
    /// which are writable, not the file's mode bits).
    async fn install_file(src: &Path, dest: &Path) -> Result<()> {
        Self::remove_if_exists(dest).await?;
        tokio::fs::copy(src, dest).await?;
        Ok(())
    }

    /// Write `contents` to `dest`, replacing any existing file (see
    /// [`install_file`] for why the destination is removed first).
    async fn write_fresh(dest: &Path, contents: &[u8]) -> Result<()> {
        Self::remove_if_exists(dest).await?;
        tokio::fs::write(dest, contents).await?;
        Ok(())
    }

    async fn remove_if_exists(path: &Path) -> Result<()> {
        match tokio::fs::remove_file(path).await {
            Ok(()) => Ok(()),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(e) => Err(e.into()),
        }
    }

    /// Ensure `dir` exists as a directory. If an earlier version left a *file* at
    /// that path (e.g. the pre-NoCloud layout wrote `<script.name>` as a file
    /// where we now want a seed directory), `create_dir_all` would fail with
    /// EEXIST — so replace the stale file first. `/run/pxe-boot` persists across
    /// service restarts, so this collision is hit on upgrade until the leftover
    /// is cleared.
    async fn ensure_dir(dir: &Path) -> Result<()> {
        if let Ok(meta) = tokio::fs::metadata(dir).await {
            if !meta.is_dir() {
                tokio::fs::remove_file(dir).await?;
            }
        }
        tokio::fs::create_dir_all(dir).await?;
        Ok(())
    }
}

#[async_trait]
impl AutoinstallPreparing for AutoinstallManager {
    async fn prepare(
        &self,
        config: &PxeBootConfig,
        distro_by_iso: &HashMap<String, DistroType>,
    ) -> Result<()> {
        AutoinstallManager::prepare(self, config, distro_by_iso).await
    }
}

/// Test double for [`AutoinstallPreparing`] -- `pub` so `lib.rs`'s test
/// module can use it too (see the note on `FakeIsoDiscovery`).
#[cfg(test)]
pub struct FakeAutoinstallPreparing {
    fail_with: Option<String>,
}

#[cfg(test)]
impl FakeAutoinstallPreparing {
    pub fn always_succeeding() -> Self {
        Self { fail_with: None }
    }

    pub fn failing_with(reason: &str) -> Self {
        Self {
            fail_with: Some(reason.to_string()),
        }
    }
}

#[cfg(test)]
#[async_trait]
impl AutoinstallPreparing for FakeAutoinstallPreparing {
    async fn prepare(
        &self,
        _config: &PxeBootConfig,
        _distro_by_iso: &HashMap<String, DistroType>,
    ) -> Result<()> {
        match &self.fail_with {
            Some(reason) => Err(crate::error::PxeBootError::Config(reason.clone())),
            None => Ok(()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::{AutoinstallScript, HttpConfig};

    fn config_with(runtime_root: &Path, iso: &str, script_src: &Path, script_name: &str) -> PxeBootConfig {
        let mut autoinstall = HashMap::new();
        autoinstall.insert(
            iso.to_string(),
            vec![AutoinstallScript {
                name: script_name.to_string(),
                script_path: script_src.to_path_buf(),
            }],
        );
        PxeBootConfig {
            iso_folder_paths: vec![PathBuf::from("/data/iso")],
            tftp_root: PathBuf::from("/srv/pxeboot"),
            runtime_root: runtime_root.to_path_buf(),
            dhcp_interfaces: vec![],
            autoinstall,
            http: HttpConfig { port: 1337 },
        }
    }

    #[tokio::test]
    async fn ubuntu_writes_user_data_and_meta_data() {
        let rt = tempfile::tempdir().unwrap();
        let src = rt.path().join("src.yaml");
        tokio::fs::write(&src, b"#cloud-config\nautoinstall:\n  version: 1\n")
            .await
            .unwrap();

        let iso = "ubuntu-26.04-live-server-amd64.iso";
        let cfg = config_with(rt.path(), iso, &src, "minimal-environment.yaml");
        let mgr = AutoinstallManager::new(rt.path().to_path_buf());

        let mut distro = HashMap::new();
        distro.insert(iso.to_string(), DistroType::Ubuntu);

        mgr.prepare(&cfg, &distro).await.unwrap();

        // NoCloud seed lives in a per-script directory as user-data + meta-data.
        let seed = rt
            .path()
            .join("unattented-install")
            .join(iso)
            .join("minimal-environment.yaml");
        let user_data = seed.join("user-data");
        assert!(user_data.is_file(), "user-data must be written");
        assert!(seed.join("meta-data").is_file(), "meta-data must be written");
        assert!(tokio::fs::read_to_string(&user_data)
            .await
            .unwrap()
            .contains("autoinstall"));
    }

    #[tokio::test]
    async fn replaces_stale_file_at_seed_path() {
        let rt = tempfile::tempdir().unwrap();
        let src = rt.path().join("src.yaml");
        tokio::fs::write(&src, b"#cloud-config\nautoinstall:\n  version: 1\n")
            .await
            .unwrap();

        let iso = "ubuntu-26.04-live-server-amd64.iso";
        // Simulate an older version that wrote the script as a *file* at the path
        // where the new code wants a seed *directory* (the /run leftover that
        // crashed the service with EEXIST).
        let iso_dir = rt.path().join("unattented-install").join(iso);
        tokio::fs::create_dir_all(&iso_dir).await.unwrap();
        tokio::fs::write(iso_dir.join("minimal-environment.yaml"), b"old-file")
            .await
            .unwrap();

        let cfg = config_with(rt.path(), iso, &src, "minimal-environment.yaml");
        let mgr = AutoinstallManager::new(rt.path().to_path_buf());
        let mut distro = HashMap::new();
        distro.insert(iso.to_string(), DistroType::Ubuntu);

        // Must not error with EEXIST; the stale file is replaced by the seed dir.
        mgr.prepare(&cfg, &distro).await.unwrap();

        let seed = iso_dir.join("minimal-environment.yaml");
        assert!(seed.is_dir(), "seed path must become a directory");
        assert!(seed.join("user-data").is_file());
        assert!(seed.join("meta-data").is_file());
    }

    #[tokio::test]
    async fn non_ubuntu_writes_script_verbatim() {
        let rt = tempfile::tempdir().unwrap();
        let src = rt.path().join("ks.cfg");
        tokio::fs::write(&src, b"# kickstart\n").await.unwrap();

        let iso = "rhel-10.2-x86_64-dvd.iso";
        let cfg = config_with(rt.path(), iso, &src, "minimal-environment.kstart");
        let mgr = AutoinstallManager::new(rt.path().to_path_buf());

        let mut distro = HashMap::new();
        distro.insert(iso.to_string(), DistroType::RedHat);

        mgr.prepare(&cfg, &distro).await.unwrap();

        let iso_dir = rt.path().join("unattented-install").join(iso);
        assert!(
            iso_dir.join("minimal-environment.kstart").is_file(),
            "kickstart is served verbatim under its own name"
        );
        assert!(
            !iso_dir.join("user-data").exists(),
            "no NoCloud files for non-Ubuntu distros"
        );
    }

    #[tokio::test]
    async fn overwrites_a_read_only_destination_from_a_prior_run() {
        // B16: a /nix/store-sourced copy is 0444 (read-only) -- see
        // `install_file`'s doc comment. A prior `prepare()` run leaves
        // the destination in exactly that mode; without the
        // remove-then-create fix, the NEXT run's overwrite attempt
        // would fail with "Permission denied" since this service runs
        // without CAP_DAC_OVERRIDE and the destination file itself
        // (not its parent directory) denies the write.
        let rt = tempfile::tempdir().unwrap();
        let src = rt.path().join("ks.cfg");
        tokio::fs::write(&src, b"# new kickstart content\n")
            .await
            .unwrap();

        let iso = "rhel-10.2-x86_64-dvd.iso";
        let cfg = config_with(rt.path(), iso, &src, "minimal-environment.kstart");
        let mgr = AutoinstallManager::new(rt.path().to_path_buf());
        let mut distro = HashMap::new();
        distro.insert(iso.to_string(), DistroType::RedHat);

        // Simulate the destination left over from a prior run, with the
        // SAME read-only mode `tokio::fs::copy` would have produced.
        let iso_dir = rt.path().join("unattented-install").join(iso);
        tokio::fs::create_dir_all(&iso_dir).await.unwrap();
        let dest = iso_dir.join("minimal-environment.kstart");
        tokio::fs::write(&dest, b"# stale old content\n")
            .await
            .unwrap();
        let mut perms = tokio::fs::metadata(&dest).await.unwrap().permissions();
        perms.set_readonly(true);
        tokio::fs::set_permissions(&dest, perms).await.unwrap();

        // Must not error with "Permission denied", and the content must
        // actually be the NEW source's, not the stale read-only one.
        mgr.prepare(&cfg, &distro).await.unwrap();

        let contents = tokio::fs::read_to_string(&dest).await.unwrap();
        assert_eq!(contents, "# new kickstart content\n");
    }

    #[tokio::test]
    async fn overwrites_a_read_only_ubuntu_meta_data_from_a_prior_run() {
        // Same regression, but for write_fresh's call site (Ubuntu's
        // always-written meta-data, not install_file's copy path).
        let rt = tempfile::tempdir().unwrap();
        let src = rt.path().join("src.yaml");
        tokio::fs::write(&src, b"#cloud-config\nautoinstall:\n  version: 1\n")
            .await
            .unwrap();

        let iso = "ubuntu-26.04-live-server-amd64.iso";
        let cfg = config_with(rt.path(), iso, &src, "minimal-environment.yaml");
        let mgr = AutoinstallManager::new(rt.path().to_path_buf());
        let mut distro = HashMap::new();
        distro.insert(iso.to_string(), DistroType::Ubuntu);

        let seed_dir = rt
            .path()
            .join("unattented-install")
            .join(iso)
            .join("minimal-environment.yaml");
        tokio::fs::create_dir_all(&seed_dir).await.unwrap();
        let meta_data = seed_dir.join("meta-data");
        tokio::fs::write(&meta_data, b"stale").await.unwrap();
        let mut perms = tokio::fs::metadata(&meta_data)
            .await
            .unwrap()
            .permissions();
        perms.set_readonly(true);
        tokio::fs::set_permissions(&meta_data, perms)
            .await
            .unwrap();

        mgr.prepare(&cfg, &distro).await.unwrap();

        let contents = tokio::fs::read_to_string(&meta_data).await.unwrap();
        assert_eq!(contents, "", "meta-data must be replaced with the fresh (empty) content");
    }

    #[tokio::test]
    async fn one_scripts_failure_does_not_block_another_scripts_write() {
        // C34: before concurrency, this loop used `?` per-iteration, so a
        // failure on an EARLIER script would short-circuit and never even
        // attempt a LATER one. Now every script's write is independently
        // attempted regardless of the others -- this test would have
        // failed under the old sequential code if "missing" sorted before
        // "present" (HashMap/Vec iteration order placed it first).
        let rt = tempfile::tempdir().unwrap();
        let good_src = rt.path().join("good.yaml");
        tokio::fs::write(&good_src, b"ok").await.unwrap();
        let missing_src = rt.path().join("does-not-exist.yaml");

        let iso = "rhel-9.6-x86_64-dvd.iso";
        let mut autoinstall = HashMap::new();
        autoinstall.insert(
            iso.to_string(),
            vec![
                AutoinstallScript {
                    name: "aaa-missing.ks".to_string(),
                    script_path: missing_src,
                },
                AutoinstallScript {
                    name: "zzz-present.ks".to_string(),
                    script_path: good_src,
                },
            ],
        );
        let cfg = PxeBootConfig {
            iso_folder_paths: vec![PathBuf::from("/data/iso")],
            tftp_root: PathBuf::from("/srv/pxeboot"),
            runtime_root: rt.path().to_path_buf(),
            dhcp_interfaces: vec![],
            autoinstall,
            http: HttpConfig { port: 1337 },
        };
        let mgr = AutoinstallManager::new(rt.path().to_path_buf());

        let result = mgr.prepare(&cfg, &HashMap::new()).await;

        assert!(result.is_err(), "the missing source file must surface as an error");
        let present_dest = rt
            .path()
            .join("unattented-install")
            .join(iso)
            .join("zzz-present.ks");
        assert!(
            present_dest.exists(),
            "the OTHER script's write must still happen, independent of the missing one's failure"
        );
    }
}
