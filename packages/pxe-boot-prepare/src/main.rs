use clap::Parser;
use pxe_boot_prepare::config::PxeBootConfig;
use pxe_boot_prepare::error::IoResultExt;
use pxe_boot_prepare::PxeBootService;
use std::path::PathBuf;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[derive(Parser)]
#[command(name = "pxe-boot-prepare")]
#[command(about = "Prepare PXE boot environment from ISO files", long_about = None)]
struct Cli {
    /// Configuration file path
    #[arg(short, long, default_value = "/etc/pxe-boot-prepare/config.json")]
    config: PathBuf,

    /// Log level
    #[arg(short, long, default_value = "info")]
    log_level: String,

    #[command(subcommand)]
    command: Commands,
}

#[derive(clap::Subcommand)]
enum Commands {
    /// Prepare PXE boot environment
    Prepare,

    /// Cleanup mounted ISOs
    Cleanup,

    /// List detected ISOs
    List,

    /// Show detected distro and GRUB menu-entry count per ISO
    /// (post-hoc diagnostic; mounts ISOs not already mounted by a prior
    /// `prepare` run, same privileges as `prepare` itself)
    Status,

    /// Validate configuration
    Validate,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();

    // Setup logging
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| cli.log_level.clone().into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    // Load configuration
    let config_content = tokio::fs::read_to_string(&cli.config)
        .await
        .with_path(&cli.config)?;
    let config: PxeBootConfig = serde_json::from_str(&config_content)?;

    // Validate configuration first
    config.validate()?;

    let service = PxeBootService::new(config);

    match cli.command {
        Commands::Prepare => {
            service.prepare().await?;
        }
        Commands::Cleanup => {
            service.cleanup().await?;
        }
        Commands::List => {
            let isos = service.list_isos().await?;
            if isos.is_empty() {
                println!("No ISO files found");
            } else {
                println!("Found {} ISO files:", isos.len());
                for iso in isos {
                    println!("  {}", iso.display());
                }
            }
        }
        Commands::Status => {
            let report = service.status().await?;
            if report.is_empty() {
                println!("No ISO files found");
            } else {
                for entry in report {
                    match entry.error {
                        None => println!(
                            "  {} → {} (menu entries: {})",
                            entry.file_name,
                            entry.distro.as_deref().unwrap_or("unknown"),
                            entry.menu_entries
                        ),
                        Some(err) => println!(
                            "  {} → NOT RECOGNIZED ({})",
                            entry.file_name, err
                        ),
                    }
                }
            }
        }
        Commands::Validate => {
            tracing::info!("Configuration is valid");
            println!("✓ Configuration is valid");
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use clap::CommandFactory;

    /// Clap's own recommended cheap sanity check (see its docs on
    /// `Command::debug_assert`): catches structural mistakes in the
    /// `#[derive(Parser)]`/`#[derive(Subcommand)]` definitions above
    /// (e.g. conflicting arg names/short flags) at test time instead of
    /// only at first real invocation.
    #[test]
    fn cli_definition_is_structurally_valid() {
        Cli::command().debug_assert();
    }

    #[test]
    fn status_subcommand_parses_with_defaults() {
        let cli = Cli::try_parse_from(["pxe-boot-prepare", "status"]).unwrap();

        assert!(matches!(cli.command, Commands::Status));
        assert_eq!(cli.config, PathBuf::from("/etc/pxe-boot-prepare/config.json"));
        assert_eq!(cli.log_level, "info");
    }

    #[test]
    fn status_subcommand_honors_explicit_config_and_log_level() {
        let cli = Cli::try_parse_from([
            "pxe-boot-prepare",
            "--config",
            "/tmp/custom.json",
            "--log-level",
            "debug",
            "status",
        ])
        .unwrap();

        assert!(matches!(cli.command, Commands::Status));
        assert_eq!(cli.config, PathBuf::from("/tmp/custom.json"));
        assert_eq!(cli.log_level, "debug");
    }

    #[test]
    fn status_subcommand_rejects_unexpected_positional_argument() {
        // `status` takes no arguments of its own -- a stray extra
        // positional must be a parse error, not silently ignored.
        let result = Cli::try_parse_from(["pxe-boot-prepare", "status", "extra-arg"]);

        assert!(result.is_err());
    }

    #[test]
    fn missing_subcommand_is_a_parse_error() {
        let result = Cli::try_parse_from(["pxe-boot-prepare"]);

        assert!(result.is_err());
    }

    type SubcommandCase = (&'static str, fn(&Commands) -> bool);

    #[test]
    fn all_subcommands_parse_to_their_own_variant() {
        let cases: &[SubcommandCase] = &[
            ("prepare", |c| matches!(c, Commands::Prepare)),
            ("cleanup", |c| matches!(c, Commands::Cleanup)),
            ("list", |c| matches!(c, Commands::List)),
            ("status", |c| matches!(c, Commands::Status)),
            ("validate", |c| matches!(c, Commands::Validate)),
        ];

        for (subcommand, matcher) in cases {
            let cli = Cli::try_parse_from(["pxe-boot-prepare", subcommand]).unwrap();
            assert!(matcher(&cli.command), "subcommand '{subcommand}' did not parse to its expected variant");
        }
    }
}
