use std::{
    collections::HashMap,
    sync::{Arc, RwLock},
};

use alloy::primitives::Address;
use tracing::info;

use crate::primitives::{
    registry::{Deregistration, RegistryEntry},
    SyncStateUpdate,
};

use super::{BlsPublicKey, DbResult, Operator, Registration, RegistryDb};

#[derive(Debug, Clone, Default)]
pub(crate) struct InMemoryDb {
    validator_registrations: Arc<RwLock<HashMap<BlsPublicKey, Registration>>>,
    index_to_pubkey: Arc<RwLock<HashMap<u64, BlsPublicKey>>>,
    operator_registrations: Arc<RwLock<HashMap<Address, Operator>>>,
    sync_state: Arc<RwLock<SyncStateUpdate>>,
}

#[async_trait::async_trait]
impl RegistryDb for InMemoryDb {
    async fn register_operator(&self, operator: Operator) -> DbResult<()> {
        info!(signer = %operator.signer, "InMemoryDb: register_operator");

        let mut operators = self.operator_registrations.write().unwrap();

        operators.insert(operator.signer, operator);

        Ok(())
    }

    async fn register_validators(&self, registrations: &[Registration]) -> DbResult<()> {
        info!(count = registrations.len(), "InMemoryDb: register_validators");

        let mut cache = self.validator_registrations.write().unwrap();
        let mut index_cache = self.index_to_pubkey.write().unwrap();

        for registration in registrations {
            cache.insert(registration.validator_pubkey.clone(), registration.clone());
            index_cache.insert(registration.validator_index, registration.validator_pubkey.clone());
        }

        Ok(())
    }

    async fn deregister_validators(&self, deregistrations: &[Deregistration]) -> DbResult<()> {
        info!(count = deregistrations.len(), "InMemoryDb: deregister_validators");

        let mut cache = self.validator_registrations.write().unwrap();
        for deregistration in deregistrations {
            cache.remove(&deregistration.validator_pubkey);
        }

        Ok(())
    }

    async fn list_registrations(&self) -> DbResult<Vec<Registration>> {
        let registrations = self.validator_registrations.read().unwrap();

        Ok(registrations.values().cloned().collect())
    }

    async fn get_registrations_by_pubkey(
        &self,
        pubkeys: &[BlsPublicKey],
    ) -> DbResult<Vec<Registration>> {
        let registrations = self.validator_registrations.read().unwrap();

        Ok(pubkeys.iter().filter_map(|pubkey| registrations.get(pubkey)).cloned().collect())
    }

    async fn list_validators(&self) -> DbResult<Vec<RegistryEntry>> {
        let registrations = self.validator_registrations.read().unwrap();
        let operators = self.operator_registrations.read().unwrap();

        let entries = registrations
            .values()
            .filter_map(|r| {
                let op = operators.get(&r.operator)?;

                Some(RegistryEntry {
                    validator_pubkey: r.validator_pubkey.clone(),
                    operator: r.operator,
                    gas_limit: r.gas_limit,
                    rpc_endpoint: op.rpc_endpoint.clone(),
                })
            })
            .collect();

        Ok(entries)
    }

    async fn get_validators_by_pubkey(
        &self,
        pubkeys: &[BlsPublicKey],
    ) -> DbResult<Vec<RegistryEntry>> {
        let registrations = self.validator_registrations.read().unwrap();
        let operators = self.operator_registrations.read().unwrap();

        Ok(pubkeys
            .iter()
            .filter_map(|pubkey| {
                let registration = registrations.get(pubkey)?;
                let operator = operators.get(&registration.operator)?;

                Some(RegistryEntry {
                    validator_pubkey: registration.validator_pubkey.clone(),
                    operator: registration.operator,
                    gas_limit: registration.gas_limit,
                    rpc_endpoint: operator.rpc_endpoint.clone(),
                })
            })
            .collect())
    }

    async fn get_validators_by_index(&self, indices: Vec<u64>) -> DbResult<Vec<RegistryEntry>> {
        let registrations = self.validator_registrations.read().unwrap();
        let operators = self.operator_registrations.read().unwrap();
        let index_cache = self.index_to_pubkey.read().unwrap();

        Ok(indices
            .iter()
            .filter_map(|&index| {
                let pubkey = index_cache.get(&index)?;
                let registration = registrations.get(pubkey)?;
                let operator = operators.get(&registration.operator)?;

                Some(RegistryEntry {
                    validator_pubkey: registration.validator_pubkey.clone(),
                    operator: registration.operator,
                    gas_limit: registration.gas_limit,
                    rpc_endpoint: operator.rpc_endpoint.clone(),
                })
            })
            .collect())
    }

    async fn list_operators(&self) -> DbResult<Vec<Operator>> {
        let operators = self.operator_registrations.read().unwrap();

        Ok(operators.values().cloned().collect())
    }

    async fn get_operators_by_signer(&self, signers: &[Address]) -> DbResult<Vec<Operator>> {
        let operators = self.operator_registrations.read().unwrap();

        Ok(signers.iter().filter_map(|signer| operators.get(signer).cloned()).collect())
    }

    async fn get_sync_state(&self) -> DbResult<SyncStateUpdate> {
        let sync_state = self.sync_state.read().unwrap();
        Ok(sync_state.clone())
    }

    async fn update_sync_state(&self, state: SyncStateUpdate) -> DbResult<()> {
        let mut sync_state = self.sync_state.write().unwrap();
        *sync_state = state;

        Ok(())
    }
}
