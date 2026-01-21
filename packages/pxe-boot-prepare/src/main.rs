use clap::Parser;
use pxe_boot_prepare::config::PxeBootConfig;
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
    let config_content = tokio::fs::read_to_string(&cli.config).await?;
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
        Commands::Validate => {
            tracing::info!("Configuration is valid");
            println!("✓ Configuration is valid");
        }
    }

    Ok(())
}
