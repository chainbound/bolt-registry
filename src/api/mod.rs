//! Module `api` contains the API server for the registry. The API server is defined in
//! [`spec::ApiSpec`];

use std::{io, net::SocketAddr, sync::Arc};

use actions::{Action, ActionStream};
use axum::{extract::State, response::IntoResponse, routing::get, Json, Router};
use reqwest::StatusCode;
use spec::{ValidatorSpec, VALIDATORS_REGISTER_PATH};
use tokio::{net::TcpListener, sync::mpsc, task::JoinHandle};

use crate::primitives::{
    registry::{Deregistration, Lookahead, Operator, Registration, RegistryEntry},
    Address, BlsPublicKey,
};

pub(crate) mod actions;

mod spec;

/// The registry API server, implementing the [`spec::ApiSpec`] trait.
pub(crate) struct RegistryApi {
    cfg: ApiConfig,
    /// Sender notifying event listeners of API events.
    tx: mpsc::Sender<Action>,
}

#[derive(Debug)]
pub(crate) struct ApiConfig {
    listen_addr: SocketAddr,
    action_buffer: usize,
}

impl Default for ApiConfig {
    fn default() -> Self {
        Self { action_buffer: 256, listen_addr: "0.0.0.0:8080".parse().unwrap() }
    }
}

impl RegistryApi {
    pub(crate) fn new(config: ApiConfig) -> (Self, ActionStream) {
        let (tx, rx) = mpsc::channel(config.action_buffer);

        let api = Self { cfg: config, tx };
        let stream = ActionStream::new(rx);

        (api, stream)
    }

    /// Spawns the API server. Returns error if the server fails to bind to the listen address.
    pub(crate) async fn spawn(self) -> Result<JoinHandle<()>, io::Error> {
        let listen_addr = self.cfg.listen_addr;
        let state = Arc::new(self);

        let router =
            Router::new().route(VALIDATORS_REGISTER_PATH, get(Self::register)).with_state(state);

        let listener = TcpListener::bind(&listen_addr).await?;

        Ok(tokio::spawn(async move {
            axum::serve(listener, router).await.unwrap();
        }))
    }

    // TODO: rest of these methods
    async fn register(
        State(api): State<Arc<RegistryApi>>,
        Json(registration): Json<Registration>,
    ) -> impl IntoResponse {
        api.register(registration).await.unwrap();

        StatusCode::OK
    }
}

impl spec::ValidatorSpec for RegistryApi {
    async fn register(&self, registration: Registration) -> Result<(), spec::RegistryError> {
        todo!()
    }

    async fn deregister(&self, deregistration: Deregistration) -> Result<(), spec::RegistryError> {
        todo!()
    }

    async fn get_registrations(&self) -> Result<Vec<Registration>, spec::RegistryError> {
        todo!()
    }
}

impl spec::DiscoverySpec for RegistryApi {
    async fn get_validators(&self) -> Result<Vec<RegistryEntry>, spec::RegistryError> {
        todo!()
    }

    async fn get_validators_by_pubkeys(
        &self,
        pubkeys: Vec<BlsPublicKey>,
    ) -> Result<Vec<RegistryEntry>, spec::RegistryError> {
        todo!()
    }

    async fn get_validators_by_indices(
        &self,
        indices: Vec<usize>,
    ) -> Result<Vec<RegistryEntry>, spec::RegistryError> {
        todo!()
    }

    async fn get_validator_by_pubkey(
        &self,
        pubkey: crate::primitives::BlsPublicKey,
    ) -> Result<RegistryEntry, spec::RegistryError> {
        todo!()
    }

    async fn get_operators(&self) -> Result<Vec<Operator>, spec::RegistryError> {
        todo!()
    }

    async fn get_operator_by_signer(
        &self,
        signer: Address,
    ) -> Result<Operator, spec::RegistryError> {
        todo!()
    }

    async fn get_lookahead(&self, epoch: u64) -> Result<Lookahead, spec::RegistryError> {
        todo!()
    }
}
