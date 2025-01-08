//! Entrypoint.

use tokio_stream::StreamExt;
use tracing::{error, info};

mod api;
use api::{actions::Action, ApiConfig, RegistryApi};

mod db;
use db::SQLDb;

mod primitives;

mod registry;
use registry::Registry;

mod sources;

mod sync;

mod cli;

#[tokio::main]
async fn main() -> eyre::Result<()> {
    tracing_subscriber::fmt::init();

    info!("Starting bolt registry server...");

    let config = cli::Opts::parse_config()?;

    let db = SQLDb::new(&config.db_url).await?;
    let mut registry = Registry::new(config, db);

    let (srv, mut actions) = RegistryApi::new(ApiConfig::default());

    if let Err(e) = srv.spawn().await {
        error!("Failed to start API server: {}", e);
    }

    while let Some(action) = actions.next().await {
        match action {
            Action::Register { registration, response } => todo!(),
            Action::Deregister { deregistration, response } => todo!(),
            Action::GetRegistrations { response } => todo!(),
            Action::GetValidators { response } => todo!(),
            Action::GetValidatorsByPubkeys { pubkeys, response } => todo!(),
            Action::GetValidatorsByIndices { indices, response } => todo!(),
            Action::GetLookahead { epoch, response } => todo!(),
            Action::GetOperator { signer, response } => todo!(),
            Action::GetValidatorByPubkey { pubkey, response } => todo!(),
            Action::GetOperators { response } => todo!(),
        }
    }

    Ok(())
}
