use std::sync::{Arc, RwLock};

use alloy::primitives::Address;
use tracing::info;

use super::{BlsPublicKey, DbResult, Operator, Registration, RegistryDb};

#[derive(Debug, Clone, Default)]
pub(crate) struct InMemoryDb {
    validator_registrations: Arc<RwLock<Vec<Registration>>>,
    operator_registrations: Arc<RwLock<Vec<Operator>>>,
}

#[async_trait::async_trait]
impl RegistryDb for InMemoryDb {
    async fn register_validators(&self, registration: Registration) -> DbResult<()> {
        info!(
            keys_count = registration.validator_pubkeys.len(),
            sig_count = registration.signatures.len(),
            digest = ?registration.digest(),
            "InMemoryDb: register_validators"
        );

        let mut registrations = self.validator_registrations.write().unwrap();
        registrations.push(registration);

        Ok(())
    }

    async fn register_operator(&self, operator: Operator) -> DbResult<()> {
        info!(signer = %operator.signer, "InMemoryDb: register_operator");

        let mut operators = self.operator_registrations.write().unwrap();
        operators.push(operator);

        Ok(())
    }

    async fn get_operator(&self, signer: Address) -> DbResult<Option<Operator>> {
        let operators = self.operator_registrations.read().unwrap();
        let operator = operators.iter().find(|op| op.signer == signer);

        match operator {
            Some(op) => Ok(Some(op.clone())),
            None => Ok(None),
        }
    }

    async fn get_validator_registration(
        &self,
        pubkey: BlsPublicKey,
    ) -> DbResult<Option<Registration>> {
        let registrations = self.validator_registrations.read().unwrap();
        let registration = registrations.iter().find(|reg| reg.validator_pubkeys.contains(&pubkey));

        match registration {
            Some(reg) => Ok(Some(reg.clone())),
            None => Ok(None),
        }
    }
}
