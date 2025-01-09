use alloy::primitives::Address;

use crate::primitives::BlsSignature;

use super::{
    BlsPublicKey, DbResult, Deregistration, Operator, Registration, RegistryDb, RegistryEntry,
};

#[derive(Debug, Clone)]
pub(crate) struct NoOpDb;

impl RegistryDb for NoOpDb {
    async fn register_validators(&self, _registration: &[Registration]) -> DbResult<()> {
        Ok(())
    }

    async fn deregister_validators(&self, _deregistration: &[Deregistration]) -> DbResult<()> {
        Ok(())
    }

    async fn register_operator(&self, _operator: Operator) -> DbResult<()> {
        Ok(())
    }

    async fn list_registrations(&self) -> DbResult<Vec<Registration>> {
        Ok(vec![])
    }

    async fn get_registrations_by_pubkey(
        &self,
        pubkeys: &[BlsPublicKey],
    ) -> DbResult<Vec<Registration>> {
        Ok(vec![Registration {
            validator_pubkey: pubkeys.first().unwrap().clone(),
            operator: Address::random(),
            gas_limit: 0,
            expiry: 0,
            signature: BlsSignature::empty(),
        }])
    }

    async fn list_validators(&self) -> DbResult<Vec<RegistryEntry>> {
        Ok(vec![])
    }

    async fn get_validators_by_pubkey(
        &self,
        pubkeys: &[BlsPublicKey],
    ) -> DbResult<Vec<RegistryEntry>> {
        Ok(vec![RegistryEntry {
            validator_pubkey: pubkeys.first().unwrap().clone(),
            operator: Address::random(),
            gas_limit: 0,
            rpc_endpoint: "https://grugbrain.dev".parse()?,
        }])
    }

    async fn get_operators(&self, _signers: Option<&[Address]>) -> DbResult<Vec<Operator>> {
        Ok(vec![])
    }
}
