use std::collections::HashMap;

use crate::primitives::{registry::RegistryEntry, BlsPublicKey};

use super::{ExternalSource, SourceError};

pub(crate) struct MockSource {
    pub(crate) entries: HashMap<BlsPublicKey, RegistryEntry>,
}

impl MockSource {
    pub(crate) fn new() -> Self {
        Self { entries: HashMap::new() }
    }

    pub(crate) fn add_entry(&mut self, entry: RegistryEntry) {
        self.entries.insert(entry.validator_pubkey.clone(), entry);
    }
}

#[async_trait::async_trait]
impl ExternalSource for MockSource {
    fn name(&self) -> &'static str {
        "mock"
    }

    async fn get_validators(
        &self,
        pubkeys: &[BlsPublicKey],
    ) -> Result<Vec<RegistryEntry>, SourceError> {
        Ok(pubkeys.iter().filter_map(|pubkey| self.entries.get(pubkey).cloned()).collect())
    }
}
