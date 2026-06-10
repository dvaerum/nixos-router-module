use std::path::PathBuf;
use thiserror::Error;

#[derive(Error, Debug)]
pub enum PxeBootError {
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),

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

    #[error("Autoinstall script not found: {0}")]
    AutoinstallNotFound(String),

    #[error("File not found: {0}")]
    FileNotFound(PathBuf),

    #[error("Template error: {0}")]
    Template(#[from] handlebars::RenderError),

    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),
}

pub type Result<T> = std::result::Result<T, PxeBootError>;
