use std::collections::HashMap;

use alloy::primitives::{Address, U256};
use serde::{Deserialize, Serialize};
use sha2::{Digest as _, Sha256};
use url::Url;
use utoipa::ToSchema;

use super::{BlsPublicKey, BlsSignature, Digest};

/// A batch registration of validators.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub(crate) struct RegistrationBatch {
    /// Validators being registered.
    pub(crate) validator_pubkeys: Vec<BlsPublicKey>,
    /// Operator that can sign commitments on behalf of the validators.
    #[schema(value_type = String)]
    pub(crate) operator: Address,
    /// Gas limit reserved for commitments.
    pub(crate) gas_limit: u64,
    /// Expiry of this registration. Good practice for off-chain components.
    /// Would also allow for a more dynamic setup if needed.
    /// If set to 0, never expires
    pub(crate) expiry: u64, // UNIX timestamp value in seconds
    /// Signatures would be: sign(digest(`operator` + `gas_limit` + `expiry`))
    #[schema(value_type = Vec<String>)]
    pub(crate) signatures: Vec<BlsSignature>,
}

impl RegistrationBatch {
    /// Returns the digest of the registration.
    pub(crate) fn digest(&self) -> Digest {
        let mut hasher = Sha256::new();
        hasher.update(self.operator.0);

        // IMPORTANT: use big-endian encoding for cross-platform compatibility
        hasher.update(self.gas_limit.to_be_bytes());
        hasher.update(self.expiry.to_be_bytes());

        let arr: [u8; 32] = hasher.finalize().into();
        arr.into()
    }

    /// Consumes the batch and returns the individual registrations.
    /// Also requires a map of validator public keys to their indices in the beacon chain.
    ///
    /// Note: if a validator index is not found in the map, the registration is skipped.
    pub(crate) fn into_items(self, index_map: HashMap<BlsPublicKey, u64>) -> Vec<Registration> {
        self.validator_pubkeys
            .into_iter()
            .zip(self.signatures)
            .filter_map(|(validator_pubkey, signature)| {
                Some(Registration {
                    validator_index: *index_map.get(&validator_pubkey)?,
                    validator_pubkey,
                    operator: self.operator,
                    gas_limit: self.gas_limit,
                    expiry: self.expiry,
                    signature: Some(signature),
                })
            })
            .collect()
    }
}

/// A single registration of a validator.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub(crate) struct Registration {
    /// Validator being registered.
    pub(crate) validator_pubkey: BlsPublicKey,
    /// Index of the validator in the beacon chain.
    pub(crate) validator_index: u64,
    /// Operator that can sign commitments on behalf of the validator.
    #[schema(value_type = String)]
    pub(crate) operator: Address,
    /// Gas limit reserved for commitments.
    pub(crate) gas_limit: u64,
    /// The expiry of the registration.
    pub(crate) expiry: u64,
    /// The BLS signature of the validator on the registration.
    #[schema(value_type = Option<String>)]
    pub(crate) signature: Option<BlsSignature>,
}

/// A batch deregistration of validators.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub(crate) struct DeregistrationBatch {
    /// Validators being de-registered.
    pub(crate) validator_pubkeys: Vec<BlsPublicKey>,
    /// Not strictly needed, but will determine signature digest.
    #[schema(value_type = String)]
    pub(crate) operator: Address,
    /// Signatures would be: sign(digest(operator))
    #[schema(value_type = Vec<String>)]
    pub(crate) signatures: Vec<BlsSignature>,
}

impl DeregistrationBatch {
    /// Consumes the batch and returns the individual de-registrations.
    pub(crate) fn into_items(self) -> Vec<Deregistration> {
        self.validator_pubkeys
            .into_iter()
            .zip(self.signatures)
            .map(|(validator_pubkey, signature)| Deregistration {
                validator_pubkey,
                operator: self.operator,
                signature,
            })
            .collect()
    }
}

/// A single deregistration of a validator.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub(crate) struct Deregistration {
    /// Validator being de-registered.
    pub(crate) validator_pubkey: BlsPublicKey,
    /// Operator that can sign commitments on behalf of the validator.
    #[schema(value_type = String)]
    pub(crate) operator: Address,
    /// The BLS signature of the validator on the de-registration.
    #[schema(value_type = String)]
    pub(crate) signature: BlsSignature,
}

/// An entry in the validator registry.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub(crate) struct RegistryEntry {
    pub(crate) validator_pubkey: BlsPublicKey,
    #[schema(value_type = String)]
    pub(crate) operator: Address,
    pub(crate) gas_limit: u64,
    #[schema(value_type = String)]
    pub(crate) rpc_endpoint: Url,
}

/// An operator in the registry.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub(crate) struct Operator {
    #[schema(value_type = String)]
    pub(crate) signer: Address,
    #[schema(value_type = String)]
    pub(crate) rpc_endpoint: Url,
    #[schema(value_type = Vec<String>)]
    pub(crate) collateral_tokens: Vec<Address>,
    #[schema(value_type = Vec<u64>)]
    pub(crate) collateral_amounts: Vec<U256>,
}

/// A lookahead representation.
pub(crate) type Lookahead = HashMap<u64, RegistryEntry>;
