//! Module `api` contains the API server for the registry. The API server is defined in
//! [`spec::ApiSpec`];

use axum::{
    extract::{Path, Query, State},
    response::IntoResponse,
    routing::get,
    Json, Router,
};
use std::{io, net::SocketAddr, sync::Arc, time::Duration};
use tokio::{
    net::TcpListener,
    sync::{
        mpsc::{self, error::SendTimeoutError},
        oneshot,
    },
    task::JoinHandle,
};

use crate::primitives::{
    registry::{Deregistration, Lookahead, Operator, Registration, RegistryEntry},
    Address, BlsPublicKey,
};
use actions::{Action, ActionStream};
use spec::{DiscoverySpec, ValidatorSpec, VALIDATORS_REGISTER_PATH};

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
    /// The size of the action buffer channel.
    action_buffer: usize,
    /// Timeout for sending actions on the channel.
    /// If the channel is full, the send operation will wait for this duration before returning an
    /// error.
    send_timeout: Duration,
}

impl Default for ApiConfig {
    fn default() -> Self {
        Self {
            action_buffer: 256,
            send_timeout: Duration::from_secs(2),
            listen_addr: "0.0.0.0:8080".parse().unwrap(),
        }
    }
}

impl RegistryApi {
    /// Creates a new API server with the given configuration. Returns the server that can be
    /// spawned with [`RegistryApi::spawn`], and the action stream on which API queries and commands
    /// are sent.
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

    async fn register(
        State(api): State<Arc<Self>>,
        Json(registration): Json<Registration>,
    ) -> impl IntoResponse {
        api.register(registration).await
    }

    async fn deregister(
        State(api): State<Arc<Self>>,
        Json(deregistration): Json<Deregistration>,
    ) -> impl IntoResponse {
        api.deregister(deregistration).await
    }

    async fn get_registrations(State(api): State<Arc<Self>>) -> impl IntoResponse {
        api.get_registrations().await.map(Json)
    }

    async fn get_validators(State(api): State<Arc<Self>>) -> impl IntoResponse {
        api.get_validators().await.map(Json)
    }

    async fn get_validators_by_pubkeys(
        State(api): State<Arc<Self>>,
        Query(pubkeys): Query<Vec<BlsPublicKey>>,
    ) -> impl IntoResponse {
        api.get_validators_by_pubkeys(pubkeys).await.map(Json)
    }

    async fn get_validators_by_indices(
        State(api): State<Arc<Self>>,
        Query(indices): Query<Vec<usize>>,
    ) -> impl IntoResponse {
        api.get_validators_by_indices(indices).await.map(Json)
    }

    async fn get_validator_by_pubkey(
        State(api): State<Arc<Self>>,
        Path(pubkey): Path<BlsPublicKey>,
    ) -> impl IntoResponse {
        api.get_validator_by_pubkey(pubkey).await.map(Json)
    }

    async fn get_operators(State(api): State<Arc<Self>>) -> impl IntoResponse {
        api.get_operators().await.map(Json)
    }

    async fn get_operator_by_signer(
        State(api): State<Arc<Self>>,
        Path(signer): Path<Address>,
    ) -> impl IntoResponse {
        api.get_operator_by_signer(signer).await.map(Json)
    }

    async fn get_lookahead(
        State(api): State<Arc<Self>>,
        Path(epoch): Path<u64>,
    ) -> impl IntoResponse {
        api.get_lookahead(epoch).await.map(Json)
    }

    async fn send_action(&self, action: Action) -> Result<(), SendTimeoutError<Action>> {
        self.tx.send_timeout(action, self.cfg.send_timeout).await
    }
}

impl spec::ValidatorSpec for RegistryApi {
    async fn register(&self, registration: Registration) -> Result<(), spec::RegistryError> {
        let (tx, rx) = oneshot::channel();

        let action = Action::Register { registration, response: tx };
        self.send_action(action).await?;

        rx.await?
    }

    async fn deregister(&self, deregistration: Deregistration) -> Result<(), spec::RegistryError> {
        let (tx, rx) = oneshot::channel();

        let action = Action::Deregister { deregistration, response: tx };
        self.send_action(action).await?;

        rx.await?
    }

    async fn get_registrations(&self) -> Result<Vec<Registration>, spec::RegistryError> {
        let (tx, rx) = oneshot::channel();

        let action = Action::GetRegistrations { response: tx };
        self.send_action(action).await?;

        rx.await?
    }
}

impl spec::DiscoverySpec for RegistryApi {
    async fn get_validators(&self) -> Result<Vec<RegistryEntry>, spec::RegistryError> {
        let (tx, rx) = oneshot::channel();

        let action = Action::GetValidators { response: tx };
        self.send_action(action).await?;

        rx.await?
    }

    async fn get_validators_by_pubkeys(
        &self,
        pubkeys: Vec<BlsPublicKey>,
    ) -> Result<Vec<RegistryEntry>, spec::RegistryError> {
        let (tx, rx) = oneshot::channel();

        let action = Action::GetValidatorsByPubkeys { pubkeys, response: tx };
        self.send_action(action).await?;

        rx.await?
    }

    async fn get_validators_by_indices(
        &self,
        indices: Vec<usize>,
    ) -> Result<Vec<RegistryEntry>, spec::RegistryError> {
        let (tx, rx) = oneshot::channel();

        let action = Action::GetValidatorsByIndices { indices, response: tx };
        self.send_action(action).await?;

        rx.await?
    }

    async fn get_validator_by_pubkey(
        &self,
        pubkey: crate::primitives::BlsPublicKey,
    ) -> Result<RegistryEntry, spec::RegistryError> {
        let (tx, rx) = oneshot::channel();

        let action = Action::GetValidatorByPubkey { pubkey, response: tx };
        self.send_action(action).await?;

        rx.await?
    }

    async fn get_operators(&self) -> Result<Vec<Operator>, spec::RegistryError> {
        let (tx, rx) = oneshot::channel();

        let action = Action::GetOperators { response: tx };
        self.send_action(action).await?;

        rx.await?
    }

    async fn get_operator_by_signer(
        &self,
        signer: Address,
    ) -> Result<Operator, spec::RegistryError> {
        let (tx, rx) = oneshot::channel();

        let action = Action::GetOperator { signer, response: tx };
        self.send_action(action).await?;

        rx.await?
    }

    async fn get_lookahead(&self, epoch: u64) -> Result<Lookahead, spec::RegistryError> {
        let (tx, rx) = oneshot::channel();

        let action = Action::GetLookahead { epoch, response: tx };
        self.send_action(action).await?;

        rx.await?
    }
}
