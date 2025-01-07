//! Module `db` contains database related traits and implementations,
//! with registry-specific abstractions.

/// No-op database implementation.
mod noop;
pub(crate) use noop::NoOpDb;

/// SQL database backend implementation.
mod sql;
pub(crate) use sql::SQLDb;

use crate::primitives::registry::Registration;

/// Registry database trait.
#[async_trait::async_trait]
pub(crate) trait RegistryDb: Clone {
    async fn register_validators(&self, registration: Registration) -> sqlx::Result<()>;
}
