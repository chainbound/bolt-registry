//! Module `api` contains the API server for the registry. The API server is defined in
//! [`spec::ValidatorSpec`] and [`spec::DiscoverySpec`], and is implemented by [`RegistryApi`].

use std::{io, net::SocketAddr, sync::Arc, time::Duration};

use alloy::primitives::Address;
use axum::routing::{get, post};
use reqwest::Method;
use serde::Deserialize;
use tokio::{
    net::TcpListener,
    sync::{
        mpsc::{self, error::SendTimeoutError},
        oneshot,
    },
    task::JoinHandle,
};
use tower_http::{cors::CorsLayer, timeout::TimeoutLayer, trace::TraceLayer};
use tracing::error;
use utoipa::OpenApi;
use utoipa_axum::router::OpenApiRouter;
use utoipa_swagger_ui::SwaggerUi;

use crate::primitives::{
    registry::{
        DeregistrationBatch, Lookahead, Operator, Registration, RegistrationBatch, RegistryEntry,
    },
    BlsPublicKey,
};

/// API handler functions
mod handlers;

/// Actions to process.
pub(crate) mod actions;
use actions::{Action, ActionStream};

/// API specification and traits.
pub(crate) mod spec;
use spec::{
    DiscoverySpec, ValidatorSpec, DISCOVERY_LOOKAHEAD_PATH, DISCOVERY_OPERATORS_PATH,
    DISCOVERY_OPERATOR_PATH, DISCOVERY_VALIDATORS_PATH, DISCOVERY_VALIDATOR_PATH,
    VALIDATORS_DEREGISTER_PATH, VALIDATORS_REGISTER_PATH, VALIDATORS_REGISTRATIONS_PATH,
};

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

#[derive(Deserialize, Default)]
struct ValidatorFilter {
    pubkeys: Option<Vec<BlsPublicKey>>,
    indices: Option<Vec<u64>>,
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

        // All API routes are defined here:
        let (router, api_docs) = OpenApiRouter::with_openapi(handlers::ApiDoc::openapi())
            .route(VALIDATORS_REGISTER_PATH, post(handlers::register))
            .route(VALIDATORS_DEREGISTER_PATH, post(handlers::deregister))
            .route(VALIDATORS_REGISTRATIONS_PATH, get(handlers::get_registrations))
            .route(DISCOVERY_VALIDATORS_PATH, get(handlers::get_validators))
            .route(DISCOVERY_VALIDATOR_PATH, get(handlers::get_validator_by_pubkey))
            .route(DISCOVERY_OPERATORS_PATH, get(handlers::get_operators))
            .route(DISCOVERY_OPERATOR_PATH, get(handlers::get_operator_by_signer))
            .route(DISCOVERY_LOOKAHEAD_PATH, get(handlers::get_lookahead))
            .with_state(state)
            .split_for_parts();

        // This is the final router that includes the API routes,
        // middlewares and the Swagger UI:
        let router = router
            .layer(TraceLayer::new_for_http())
            .layer(TimeoutLayer::new(spec::MAX_REQUEST_TIMEOUT))
            .layer(
                CorsLayer::new()
                    .allow_origin(tower_http::cors::Any)
                    .allow_methods([Method::GET, Method::POST])
                    .allow_headers(tower_http::cors::Any),
            )
            .merge(SwaggerUi::new("/docs").url("/api-docs/openapi.json", api_docs));

        let listener = TcpListener::bind(&listen_addr).await?;

        Ok(tokio::spawn(async move {
            if let Err(err) = axum::serve(listener, router).await {
                error!("API server crashed: {}", err);
            }
        }))
    }

    async fn send_action(&self, action: Action) -> Result<(), SendTimeoutError<Action>> {
        self.tx.send_timeout(action, self.cfg.send_timeout).await
    }
}

impl spec::ValidatorSpec for RegistryApi {
    #[tracing::instrument(skip(self))]
    async fn register(&self, registration: RegistrationBatch) -> Result<(), spec::RegistryError> {
        let (tx, rx) = oneshot::channel();

        let action = Action::Register { registration, response: tx };
        self.send_action(action).await?;

        rx.await?
    }

    #[tracing::instrument(skip(self))]
    async fn deregister(
        &self,
        deregistration: DeregistrationBatch,
    ) -> Result<(), spec::RegistryError> {
        let (tx, rx) = oneshot::channel();

        let action = Action::Deregister { deregistration, response: tx };
        self.send_action(action).await?;

        rx.await?
    }

    #[tracing::instrument(skip(self))]
    async fn get_registrations(&self) -> Result<Vec<Registration>, spec::RegistryError> {
        let (tx, rx) = oneshot::channel();

        let action = Action::GetRegistrations { response: tx };
        self.send_action(action).await?;

        rx.await?
    }
}

impl spec::DiscoverySpec for RegistryApi {
    #[tracing::instrument(skip(self))]
    async fn get_validators(&self) -> Result<Vec<RegistryEntry>, spec::RegistryError> {
        let (tx, rx) = oneshot::channel();

        let action = Action::GetValidators { response: tx };
        self.send_action(action).await?;

        rx.await?
    }

    #[tracing::instrument(skip(self))]
    async fn get_validators_by_pubkeys(
        &self,
        pubkeys: Vec<BlsPublicKey>,
    ) -> Result<Vec<RegistryEntry>, spec::RegistryError> {
        let (tx, rx) = oneshot::channel();

        let action = Action::GetValidatorsByPubkeys { pubkeys, response: tx };
        self.send_action(action).await?;

        rx.await?
    }

    #[tracing::instrument(skip(self))]
    async fn get_validators_by_indices(
        &self,
        indices: Vec<u64>,
    ) -> Result<Vec<RegistryEntry>, spec::RegistryError> {
        let (tx, rx) = oneshot::channel();

        let action = Action::GetValidatorsByIndices { indices, response: tx };
        self.send_action(action).await?;

        rx.await?
    }

    #[tracing::instrument(skip(self))]
    async fn get_validator_by_pubkey(
        &self,
        pubkey: BlsPublicKey,
    ) -> Result<RegistryEntry, spec::RegistryError> {
        let (tx, rx) = oneshot::channel();

        let action = Action::GetValidatorByPubkey { pubkey, response: tx };
        self.send_action(action).await?;

        rx.await?
    }

    #[tracing::instrument(skip(self))]
    async fn get_operators(&self) -> Result<Vec<Operator>, spec::RegistryError> {
        let (tx, rx) = oneshot::channel();

        let action = Action::GetOperators { response: tx };
        self.send_action(action).await?;

        rx.await?
    }

    #[tracing::instrument(skip(self))]
    async fn get_operator_by_signer(
        &self,
        signer: Address,
    ) -> Result<Operator, spec::RegistryError> {
        let (tx, rx) = oneshot::channel();

        let action = Action::GetOperator { signer, response: tx };
        self.send_action(action).await?;

        rx.await?
    }

    #[tracing::instrument(skip(self))]
    async fn get_lookahead(&self, epoch: u64) -> Result<Lookahead, spec::RegistryError> {
        let (tx, rx) = oneshot::channel();

        let action = Action::GetLookahead { epoch, response: tx };
        self.send_action(action).await?;

        rx.await?
    }
}

#[cfg(test)]
mod tests {
    use tokio_stream::StreamExt;

    use super::*;

    #[tokio::test]
    async fn test_register() {
        let _ = tracing_subscriber::fmt().try_init();

        let (api, mut stream) = RegistryApi::new(Default::default());

        let operator = Address::random();
        let gas_limit = 10_000u64;
        let expiry = 0u64;

        let registration = RegistrationBatch {
            validator_pubkeys: vec![BlsPublicKey::random()],
            operator,
            gas_limit,
            expiry,
            signatures: vec![],
        };

        let reg_clone = registration.clone();
        tokio::spawn(async move {
            let result = api.register(reg_clone).await;
            assert!(result.is_ok());
        });

        let action = stream.next().await.unwrap();
        match action {
            Action::Register { registration: reg, response } => {
                assert_eq!(registration.digest(), reg.digest());
                response.send(Ok(())).unwrap();
            }
            _ => panic!("unexpected action"),
        }
    }
}
