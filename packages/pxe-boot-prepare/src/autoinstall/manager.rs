use crate::config::{DistroType, PxeBootConfig};
use crate::error::Result;
use std::collections::HashMap;
use std::path::{Path, PathBuf};

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

        for (iso_name, scripts) in &config.autoinstall {
            let iso_script_dir = autoinstall_root.join(iso_name);
            Self::ensure_dir(&iso_script_dir).await?;

            let is_ubuntu = matches!(distro_by_iso.get(iso_name), Some(DistroType::Ubuntu));

            for script in scripts {
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
            }
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
            iso_folder_path: PathBuf::from("/data/iso"),
            tftp_root: PathBuf::from("/srv/pxeboot"),
            runtime_root: runtime_root.to_path_buf(),
            dhcp_interfaces: vec![],
            autoinstall,
            http: HttpConfig {
                mount_port: 1337,
                iso_port: 1338,
            },
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
}
