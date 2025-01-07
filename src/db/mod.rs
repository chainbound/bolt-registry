//! Module `db` contains database related traits and implementations,
//! with registry-specific abstractions.
use std::array::TryFromSliceError;

use alloy::primitives::Address;

use crate::primitives::{
    registry::{Operator, Registration},
    BlsPublicKey,
};

mod types;

/// No-op database implementation.
mod noop;
pub(crate) use noop::NoOpDb;

/// SQL database backend implementation.
mod sql;
pub(crate) use sql::SQLDb;

pub(crate) type DbResult<T> = Result<T, DbError>;

/// Database error type.
#[derive(Debug, thiserror::Error)]
#[allow(missing_docs)]
pub(crate) enum DbError {
    #[error(transparent)]
    Sqlx(#[from] sqlx::Error),
    #[error("Failed to convert slice to address")]
    TryFromSlice(#[from] TryFromSliceError),
    #[error("Failed to parse URL: {0}")]
    ParseUrl(#[from] url::ParseError),
    #[error("Failed to parse BLS key: {0:?}")]
    ParseBLSKey(bls::Error),
    #[error("Failed to parse integer: {0}")]
    ParseUint(&'static str),
    #[error("Database invariant violation: {0}")]
    Invariant(&'static str),
}

/// Registry database trait.
#[async_trait::async_trait]
pub(crate) trait RegistryDb: Clone {
    /// Register validators in the database.
    async fn register_validators(&self, registration: Registration) -> DbResult<()>;

    /// Register an operator in the database.
    async fn register_operator(&self, operator: Operator) -> DbResult<()>;

    /// Get an operator from the database.
    async fn get_operator(&self, signer: Address) -> DbResult<Operator>;

    /// Get a validator registration from the database.
    async fn get_validator_registration(&self, pubkey: BlsPublicKey) -> DbResult<Registration>;
}
