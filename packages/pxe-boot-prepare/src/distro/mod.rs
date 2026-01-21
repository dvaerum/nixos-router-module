pub mod detector;
pub mod nixos;
pub mod rhel;
pub mod ubuntu;
pub mod unknown;

pub use detector::{DetectorRegistry, DistroDetector};
