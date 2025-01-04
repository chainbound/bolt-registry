use std::{collections::HashMap, hash::Hasher};

use alloy::primitives::{Address, U256};
use serde::{Deserialize, Serialize};
use sha2::{Digest as _, Sha256};
use url::Url;

use super::{BlsPublicKey, BlsSignature, Digest};

/// A batch registration of validators.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct Registration {
    /// Validators being registered.
    pub(crate) validator_pubkeys: Vec<BlsPublicKey>,
    /// Operator that can sign commitments on behalf of the validators.
    pub(crate) operator: Address,
    /// Gas limit reserved for commitments.
    pub(crate) gas_limit: u64,
    /// Expiry of this registration. Good practice for off-chain components.
    /// Would also allow for a more dynamic setup if needed.
    /// If set to 0, never expires
    pub(crate) expiry: u64, // UNIX timestamp value in seconds
    /// Signatures would be: sign(digest(`operator` + `gas_limit` + `expiry`))
    pub(crate) signatures: Vec<BlsSignature>,
}

impl Registration {
    /// Returns the digest of the registration.
    pub(crate) fn digest(&self) -> Digest {
        let mut hasher = Sha256::new();
        hasher.update(self.operator.0);

        // IMPORTANT: use big-endian encoding for cross-platform compatibility
        hasher.update(self.gas_limit.to_be_bytes());
        hasher.update(self.expiry.to_be_bytes());

        hasher.finalize().into()
    }
}

/// A batch deregistration of validators.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct Deregistration {
    /// Validators being de-registered.
    pub(crate) validator_pubkeys: Vec<BlsPublicKey>,
    /// Not strictly needed, but will determine signature digest.
    pub(crate) operator: Address,
    /// Signatures would be: sign(digest(operator))
    pub(crate) signatures: Vec<BlsSignature>,
}

/// An entry in the validator registry.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct RegistryEntry {
    pub(crate) validator_pubkey: BlsPublicKey,
    pub(crate) operator: Address,
    pub(crate) gas_limit: u64,
    pub(crate) rpc_endpoint: Url,
}

/// An operator in the registry.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct Operator {
    pub(crate) signer: Address,
    pub(crate) rpc_endpoint: Url,
    pub(crate) collateral_tokens: Vec<Address>,
    pub(crate) collateral_amounts: Vec<U256>,
}

/// A lookahead representation.
pub(crate) type Lookahead = HashMap<u64, RegistryEntry>;
