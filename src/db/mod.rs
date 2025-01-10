//! Module `db` contains database related traits and implementations,
//! with registry-specific abstractions.
use std::array::TryFromSliceError;

use alloy::primitives::Address;

use crate::primitives::{
    registry::{Deregistration, Operator, Registration, RegistryEntry},
    BlsPublicKey, SyncStateUpdate,
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

/// Sync transaction trait. Provides a way to atomically commit any mutations and finalize
/// with the new sync state.
#[async_trait::async_trait]
pub(crate) trait SyncTransaction {
    /// Register validators in the database.
    async fn register_validators(&mut self, registrations: &[Registration]) -> DbResult<()>;

    /// Register an operator in the database.
    async fn register_operator(&mut self, operator: Operator) -> DbResult<()>;

    async fn commit(self, state: SyncStateUpdate) -> DbResult<()>;
}

/// Registry database trait.
#[async_trait::async_trait]
pub(crate) trait RegistryDb: Clone + Send + Sync + 'static {
    type SyncTransaction: SyncTransaction + Send;

    /// Begin a new sync transaction. A sync transaction groups database mutations together in a
    /// single atomic operation.
    async fn begin_sync(&self) -> DbResult<Self::SyncTransaction>;

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

    /// Get the current sync state from the database.
    async fn get_sync_state(&self) -> DbResult<SyncStateUpdate>;

    /// Update the sync state in the database.
    async fn update_sync_state(&self, state: SyncStateUpdate) -> DbResult<()>;
}
