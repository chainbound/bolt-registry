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

    async fn get_registrations(
        &self,
        pubkeys: Option<&[BlsPublicKey]>,
    ) -> DbResult<Vec<Registration>> {
        Ok(vec![Registration {
            validator_pubkey: pubkeys.unwrap().first().unwrap().clone(),
            operator: Address::random(),
            gas_limit: 0,
            expiry: 0,
            signature: BlsSignature::empty(),
        }])
    }

    async fn get_validators(
        &self,
        pubkeys: Option<&[BlsPublicKey]>,
    ) -> DbResult<Vec<RegistryEntry>> {
        Ok(vec![RegistryEntry {
            validator_pubkey: pubkeys.unwrap().first().unwrap().clone(),
            operator: Address::random(),
            gas_limit: 0,
            rpc_endpoint: "https://grugbrain.dev".parse()?,
        }])
    }

    async fn get_operators(&self, _signers: Option<&[Address]>) -> DbResult<Vec<Operator>> {
        Ok(vec![])
    }
}
