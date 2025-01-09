//! Module `db` contains database related traits and implementations,
//! with registry-specific abstractions.
use std::array::TryFromSliceError;

use alloy::primitives::Address;

use crate::primitives::{
    registry::{Deregistration, Operator, Registration, RegistryEntry},
    BlsPublicKey,
};

mod types;

/// In-memory database implementation.
mod memory;
pub(crate) use memory::InMemoryDb;

/// SQL database backend implementation.
mod sql;
pub(crate) use sql::SQLDb;

pub(crate) type DbResult<T> = Result<T, DbError>;

/// Database error type.
// TODO: Implement `is_transient` or `is_retryable` methods.
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
#[async_trait::async_trait]
pub(crate) trait RegistryDb: Clone {
    /// Register validators in the database.
    async fn register_validators(&self, registrations: &[Registration]) -> DbResult<()>;

    /// Deregister validators in the database.
    async fn deregister_validators(&self, deregistrations: &[Deregistration]) -> DbResult<()>;

    /// Register an operator in the database.
    async fn register_operator(&self, operator: Operator) -> DbResult<()>;

    /// List all registrations in the database.
    async fn list_registrations(&self) -> DbResult<Vec<Registration>>;

    /// Get a batch of registrations from the database, by their public keys.
    async fn get_registrations_by_pubkey(
        &self,
        pubkeys: &[BlsPublicKey],
    ) -> DbResult<Vec<Registration>>;

    /// List all validators in the database.
    async fn list_validators(&self) -> DbResult<Vec<RegistryEntry>>;

    /// Get a batch of validators from the database, by their public keys..
    async fn get_validators_by_pubkey(
        &self,
        pubkeys: &[BlsPublicKey],
    ) -> DbResult<Vec<RegistryEntry>>;

    /// Get a batch of validators from the database, by their beacon chain indices.
    async fn get_validators_by_index(&self, indices: Vec<u64>) -> DbResult<Vec<RegistryEntry>>;

    /// List all operators in the database.
    async fn list_operators(&self) -> DbResult<Vec<Operator>>;

    /// Get a batch of operators from the database, by their signer addresses.
    async fn get_operators_by_signer(&self, signers: &[Address]) -> DbResult<Vec<Operator>>;
}
