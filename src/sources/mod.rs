//! Sources contain external registry data sources.
use thiserror::Error;

use crate::primitives::{registry::RegistryEntry, BlsPublicKey};

/// Lido Keys API source.
/// <https://github.com/lidofinance/lido-keys-api/tree/develop>
pub(crate) mod kapi;

#[derive(Debug, Error)]
pub(crate) enum SourceError {
    #[error(transparent)]
    Reqwest(#[from] reqwest::Error),
}

/// External source trait.
#[async_trait::async_trait]
pub(crate) trait ExternalSource {
    fn name(&self) -> &'static str;

    async fn get_validators(
        &self,
        pubkeys: &[BlsPublicKey],
    ) -> Result<Vec<RegistryEntry>, SourceError>;
}
