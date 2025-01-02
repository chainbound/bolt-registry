use alloy::primitives::Address;
use serde::{Deserialize, Serialize};
use url::Url;

use super::{BlsPublicKey, BlsSignature};

/// A batch registration of validators.
#[derive(Debug, Serialize, Deserialize)]
pub(crate) struct Registration {
    /// Validators being registered.
    validator_pubkeys: Vec<BlsPublicKey>,
    /// Operator that can sign commitments on behalf of the validators.
    operator: Address,
    /// Gas limit reserved for commitments.
    gas_limit: u64,
    /// Expiry of this registration. Good practice for off-chain components.
    /// Would also allow for a more dynamic setup if needed.
    /// If set to 0, never expires
    expiry: u64, // UNIX timestamp value in seconds
    /// Signatures would be: sign(digest(`operator` + `gas_limit` + `expiry`))
    signatures: Vec<BlsSignature>,
}

/// A batch deregistration of validators.
#[derive(Debug, Serialize, Deserialize)]
pub(crate) struct Deregistration {
    /// Validators being de-registered.
    validator_pubkeys: Vec<BlsPublicKey>,
    /// Not strictly needed, but will determine signature digest.
    operator: Address,
    /// Signatures would be: sign(digest(operator))
    signatures: Vec<BlsSignature>,
}

/// An entry in the validator registry.
#[derive(Debug, Serialize, Deserialize)]
pub(crate) struct RegistryEntry {
    validator_pubkey: BlsPublicKey,
    operator: Address,
    gas_limit: u64,
    rpc_endpoint: Url,
}
