//! Entrypoint.

use client::BeaconClient;
use tokio_stream::StreamExt;
use tracing::{error, info};
use url::Url;

mod api;
use api::{
    actions::{Action, ActionStream},
    spec::RegistryError,
    ApiConfig, RegistryApi,
};

mod client;

mod db;
use db::{InMemoryDb, RegistryDb, SQLDb};

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
    let beacon = BeaconClient::new(config.beacon_url.clone());

    let (srv, actions) = RegistryApi::new(ApiConfig::default());

    if let Err(e) = srv.spawn().await {
        error!("Failed to start API server: {}", e);
    }

    // Initialize the registry with the specified database backend.
    //
    // * If a database URL is provided, use the SQL database backend.
    // * Otherwise, use the in-memory cache backend.
    if let Some(ref db_url) = config.db_url {
        info!("Using PostgreSQL database backend");
        let db = SQLDb::new(db_url).await?;
        let registry = Registry::new(config, db, beacon);

        handle_actions(actions, registry).await;
    } else {
        info!("Using In-memory database backend");
        let db = InMemoryDb::default();
        let registry = Registry::new(config, db, beacon);

        handle_actions(actions, registry).await;
    }

    Ok(())
}

/// Handle incoming actions from the API server and update the registry.
async fn handle_actions<Db>(mut actions: ActionStream, mut registry: Registry<Db>)
where
    Db: RegistryDb,
{
    while let Some(action) = actions.next().await {
        match action {
            Action::Register { registration, response } => {
                let res = registry.register_validators(registration).await;
                let _ = response.send(res);
            }
            Action::Deregister { deregistration, response } => {
                let res = registry.deregister_validators(deregistration).await;
                let _ = response.send(res);
            }
            Action::GetRegistrations { response } => {
                let res = registry.list_registrations().await;
                let _ = response.send(res);
            }
            Action::GetValidators { response } => {
                let res = registry.list_validators().await;
                let _ = response.send(res);
            }
            Action::GetValidatorsByPubkeys { pubkeys, response } => {
                let res = registry.get_validators_by_pubkey(&pubkeys).await;
                let _ = response.send(res);
            }
            Action::GetValidatorsByIndices { indices, response } => {
                let res = registry.get_validators_by_index(indices).await;
                let _ = response.send(res);
            }
            Action::GetValidatorByPubkey { pubkey, response } => {
                let res = registry.get_validators_by_pubkey(&[pubkey]).await;
                let first_validator_res = res.map(|mut v| v.pop()).transpose();
                let _ = response.send(first_validator_res.unwrap_or(Err(RegistryError::NotFound)));
            }
            Action::GetOperator { signer, response } => {
                let res = registry.get_operators_by_signer(&[signer]).await;
                let first_operator_res = res.map(|mut o| o.pop()).transpose();
                let _ = response.send(first_operator_res.unwrap_or(Err(RegistryError::NotFound)));
            }
            Action::GetOperators { response } => {
                let res = registry.list_operators().await;
                let _ = response.send(res);
            }
            Action::GetLookahead { epoch, response } => {
                // TODO: fetch lookahead from beacon node
                // let res = registry.get_lookahead(epoch).await;
                // let _ = response.send(res);
            }
        }
    }
}
