//! Entrypoint.
use api::{actions::Action, ApiConfig, RegistryApi};
use db::DummyDb;
use registry::Registry;
use tokio_stream::StreamExt;
use tracing::error;

mod api;
mod db;
mod primitives;
mod registry;
mod sources;
mod sync;

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt::init();

    let registry = Registry::new(DummyDb);

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
}
