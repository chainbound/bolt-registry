//! The API specification for the registry, and its errors. Contains 2 sub-specs: [`ValidatorSpec`]
//! and [`DiscoverySpec`]. The [`ApiSpec`] trait combines both of these.

use std::time::Duration;

use alloy::primitives::Address;
use axum::{http::StatusCode, response::IntoResponse, Json};
use serde::{Deserialize, Serialize};
use thiserror::Error;
use tokio::sync::{mpsc::error::SendTimeoutError, oneshot::error::RecvError};

use super::actions::Action;
use crate::{
    client::beacon::BeaconClientError,
    db::DbError,
    primitives::{
        registry::{
            DeregistrationBatch, Lookahead, Operator, Registration, RegistrationBatch,
            RegistryEntry,
        },
        BlsPublicKey,
    },
};

/// The maximum request timeout for Bolt Registry API.
pub(super) const MAX_REQUEST_TIMEOUT: Duration = Duration::from_secs(30);

// validator endpoints
pub(super) const VALIDATORS_REGISTER_PATH: &str = "/registry/v1/validators/register";
pub(super) const VALIDATORS_DEREGISTER_PATH: &str = "/registry/v1/validators/deregister";
pub(super) const VALIDATORS_REGISTRATIONS_PATH: &str = "/registry/v1/validators/registrations";

// discovery endpoints
pub(super) const DISCOVERY_VALIDATORS_PATH: &str = "/registry/v1/discovery/validators";
pub(super) const DISCOVERY_VALIDATOR_PATH: &str = "/registry/v1/discovery/validators/{pubkey}";
pub(super) const DISCOVERY_OPERATORS_PATH: &str = "/registry/v1/discovery/operators";
pub(super) const DISCOVERY_OPERATOR_PATH: &str = "/registry/v1/discovery/operators/{signer}";
pub(super) const DISCOVERY_LOOKAHEAD_PATH: &str = "/registry/v1/discovery/lookahead/{epoch}";

/// The registry API spec for validators.
pub(super) trait ValidatorSpec {
    /// /registry/v1/validators/register
    async fn register(&self, registration: RegistrationBatch) -> Result<(), RegistryError>;

    /// /registry/v1/validators/deregister
    async fn deregister(&self, deregistration: DeregistrationBatch) -> Result<(), RegistryError>;

    /// /registry/v1/validators/registrations
    async fn get_registrations(&self) -> Result<Vec<Registration>, RegistryError>;
}

/// The registry API spec for discovery.
pub(super) trait DiscoverySpec {
    /// /registry/v1/discovery/validators
    async fn get_validators(&self) -> Result<Vec<RegistryEntry>, RegistryError>;

    /// /registry/v1/discovery/validators?pubkeys=...
    async fn get_validators_by_pubkeys(
        &self,
        pubkeys: Vec<BlsPublicKey>,
    ) -> Result<Vec<RegistryEntry>, RegistryError>;

    /// /registry/v1/discovery/validators?indices=...
    async fn get_validators_by_indices(
        &self,
        indices: Vec<u64>,
    ) -> Result<Vec<RegistryEntry>, RegistryError>;

    /// /registry/v1/discovery/validators/{pubkey}
    async fn get_validator_by_pubkey(
        &self,
        pubkey: BlsPublicKey,
    ) -> Result<RegistryEntry, RegistryError>;

    /// /registry/v1/discovery/operators
    async fn get_operators(&self) -> Result<Vec<Operator>, RegistryError>;

    /// /registry/v1/discovery/operators/{signer}
    async fn get_operator_by_signer(&self, signer: Address) -> Result<Operator, RegistryError>;

    /// /registry/v1/discovery/lookahead/{epoch}
    /// This will return `TooEarly` if the epoch is too far in the future.
    async fn get_lookahead(&self, epoch: u64) -> Result<Lookahead, RegistryError>;
}

#[derive(Debug, Error)]
pub(crate) enum RegistryError {
    #[error("Internal Server Error")]
    BufferFull(#[from] SendTimeoutError<Action>),
    #[error("Internal Server Error")]
    ReponseChannelDropped(#[from] RecvError),
    #[error("Not Found")]
    NotFound,
    #[error("Internal Server Error")]
    Database(#[from] DbError),
    #[error("Internal Server Error")]
    Beacon(#[from] BeaconClientError),
    #[error("Bad Request: {0}")]
    BadRequest(&'static str),
}

impl IntoResponse for RegistryError {
    fn into_response(self) -> axum::response::Response {
        match self {
            Self::BufferFull(_) |
            Self::ReponseChannelDropped(_) |
            Self::Database(_) |
            Self::Beacon(_) => {
                json_error_response(StatusCode::INTERNAL_SERVER_ERROR, "Internal Server Error")
                    .into_response()
            }
            Self::NotFound => {
                json_error_response(StatusCode::NOT_FOUND, "Not Found").into_response()
            }
            Self::BadRequest(_) => {
                json_error_response(StatusCode::BAD_REQUEST, &self.to_string()).into_response()
            }
        }
    }
}

fn json_error_response(status: StatusCode, message: &str) -> impl IntoResponse {
    (status, Json(ErrorBody { code: status.as_u16(), message })).into_response()
}

#[derive(Serialize, Deserialize)]
struct ErrorBody<'a> {
    code: u16,
    message: &'a str,
}
