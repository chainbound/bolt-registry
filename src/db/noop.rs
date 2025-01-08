use alloy::primitives::Address;

use super::{BlsPublicKey, DbResult, Operator, Registration, RegistryDb};

#[derive(Debug, Clone)]
pub(crate) struct NoOpDb;

impl RegistryDb for NoOpDb {
    async fn register_validators(&self, _registration: Registration) -> DbResult<()> {
        Ok(())
    }

    async fn register_operator(&self, _operator: Operator) -> DbResult<()> {
        Ok(())
    }

    async fn get_operator(&self, signer: Address) -> DbResult<Operator> {
        Ok(Operator {
            signer,
            rpc_endpoint: "https://grugbrain.dev".parse()?,
            collateral_tokens: vec![],
            collateral_amounts: vec![],
        })
    }

    async fn get_validator_registration(&self, pubkey: BlsPublicKey) -> DbResult<Registration> {
        Ok(Registration {
            validator_pubkeys: vec![pubkey],
            operator: Address::default(),
            gas_limit: 0,
            expiry: 0,
            signatures: vec![],
        })
    }
}
