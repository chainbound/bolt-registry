use alloy::primitives::{Address, FixedBytes};
use derive_more::derive::{Deref, DerefMut, From};
use ethereum_consensus::crypto::PublicKey;
use serde::{Deserialize, Serialize};
use sha2::{Digest as _, Sha256};

pub(crate) mod beacon;
pub(crate) mod registry;

#[derive(Debug, Clone, Serialize, Deserialize, Deref, DerefMut, From, PartialEq, Eq, Hash)]
pub(crate) struct BlsPublicKey(bls::PublicKey);

impl BlsPublicKey {
    #[cfg(test)]
    pub(crate) fn random() -> Self {
        Self(bls::Keypair::random().pk)
    }

    /// Creates a new `BlsPublicKey` from a compressed byte slice.
    pub(crate) fn from_bytes(bytes: &[u8]) -> Result<Self, bls::Error> {
        Ok(Self(bls::PublicKey::deserialize(bytes)?))
    }

    /// Converts the BLS public key to an [`ethereum_consensus::crypto::PublicKey`].
    pub(crate) fn to_consensus(&self) -> PublicKey {
        PublicKey::try_from(self.0.compress().serialize().as_ref()).unwrap()
    }
}

pub(crate) type BlsSignature = bls::Signature;

pub(crate) type Digest = FixedBytes<32>;

pub(crate) trait DigestExt {
    fn from_parts(operator: Address, gas_limit: u64, expiry: u64) -> Self;
}

impl DigestExt for Digest {
    fn from_parts(operator: Address, gas_limit: u64, expiry: u64) -> Self {
        let mut hasher = Sha256::new();
        hasher.update(operator.0);

        // IMPORTANT: use big-endian encoding for cross-platform compatibility
        hasher.update(gas_limit.to_be_bytes());
        hasher.update(expiry.to_be_bytes());

        let arr: [u8; 32] = hasher.finalize().into();
        arr.into()
    }
}

/// Sync state of the registry database.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub(crate) struct SyncStateUpdate {
    pub(crate) block_number: u64,
    pub(crate) epoch: u64,
    pub(crate) slot: u64,
}
