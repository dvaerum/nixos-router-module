use std::path::PathBuf;
use thiserror::Error;

#[derive(Error, Debug)]
pub enum PxeBootError {
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),

    /// Same underlying `io::Error` as `Io` above, but carrying the path
    /// the operation was attempted against -- `Io`'s bare `#[from]`
    /// conversion (used anywhere a bare `?` still applies) gives no way
    /// to say which file/directory a "No such file or directory" was
    /// actually about. Attached via the `IoResultExt::with_path`
    /// extension trait below at call sites worth the context.
    #[error("I/O error on {path}: {source}")]
    IoPath {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },

    #[error("Failed to write GRUB menu to {path}: {source}")]
    GrubWrite {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },

    #[error("Failed to mount ISO {path}: {reason}")]
    MountFailed { path: PathBuf, reason: String },

    #[error("Distribution detection failed for {iso}: {reason}")]
    DetectionFailed { iso: String, reason: String },

    #[error("GRUB generation failed: {0}")]
    GrubGeneration(String),

    #[error("Configuration error: {0}")]
    Config(String),

    #[error("File not found: {0}")]
    FileNotFound(PathBuf),

    #[error("Template error: {0}")]
    Template(#[from] handlebars::RenderError),

    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),
}

pub type Result<T> = std::result::Result<T, PxeBootError>;

/// Attaches a path to an `io::Error` at the call site, turning it into
/// `PxeBootError::IoPath` instead of the context-free `PxeBootError::Io`.
/// `path` takes anything `Into<PathBuf>` (a `&Path`, `PathBuf`, or
/// `&str` literal like `"/proc/mounts"`) so it can be dropped in at an
/// existing `tokio::fs::...().await?` without extra cloning ceremony at
/// most call sites.
pub trait IoResultExt<T> {
    fn with_path(self, path: impl Into<PathBuf>) -> Result<T>;
}

impl<T> IoResultExt<T> for std::result::Result<T, std::io::Error> {
    fn with_path(self, path: impl Into<PathBuf>) -> Result<T> {
        self.map_err(|source| PxeBootError::IoPath {
            path: path.into(),
            source,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn with_path_attaches_the_path_to_the_error_message() {
        let io_err = std::io::Error::new(std::io::ErrorKind::NotFound, "No such file or directory");
        let result: std::result::Result<(), std::io::Error> = Err(io_err);

        let err = result.with_path(std::path::Path::new("/srv/pxeboot/grub.cfg")).unwrap_err();

        let message = err.to_string();
        assert!(message.contains("/srv/pxeboot/grub.cfg"), "{message}");
        assert!(message.contains("No such file or directory"), "{message}");
    }
}
