//! Module `db` contains database related traits and implementations,
//! with registry-specific abstractions.
use std::array::TryFromSliceError;

use alloy::primitives::Address;

use crate::primitives::{
    registry::{Deregistration, Operator, Registration, RegistryEntry},
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
    #[error("Missing field from query result: {0}")]
    MissingField(&'static str),
}

/// Registry database trait.
pub(crate) trait RegistryDb: Clone {
    /// Register validators in the database.
    async fn register_validators(&self, registrations: &[Registration]) -> DbResult<()>;

    /// Deregister validators in the database.
    async fn deregister_validators(&self, deregistrations: &[Deregistration]) -> DbResult<()>;

    /// Register an operator in the database.
    async fn register_operator(&self, operator: Operator) -> DbResult<()>;

    /// Get an operator from the database.
    async fn get_operator(&self, signer: Address) -> DbResult<Operator>;

    /// Get a batch of registrations from the database, by their public keys.
    ///
    /// If no public keys are provided, return all registrations in the registry.
    async fn get_registrations(
        &self,
        pubkeys: Option<&[BlsPublicKey]>,
    ) -> DbResult<Vec<Registration>>;

    /// Get a batch of validators from the database, by their public keys.
    ///
    /// If no public keys are provided, return all validators in the registry.
    async fn get_validators(
        &self,
        pubkeys: Option<&[BlsPublicKey]>,
    ) -> DbResult<Vec<RegistryEntry>>;
}
