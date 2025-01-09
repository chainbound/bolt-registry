use derive_more::derive::{Deref, DerefMut, From};
use serde::{Deserialize, Serialize};

pub(crate) mod registry;

#[derive(Debug, Clone, Serialize, Deserialize, Deref, DerefMut, From, PartialEq, Eq, Hash)]
pub(crate) struct BlsPublicKey(bls::PublicKey);

impl BlsPublicKey {
    #[cfg(test)]
    pub(crate) fn random() -> Self {
        Self(bls::Keypair::random().pk)
    }

    /// Helper function to convert the public key from the `ethereum_consensus` crate.
    pub(crate) fn from_consensus(pk: ethereum_consensus::primitives::BlsPublicKey) -> Self {
        let bytes = bls::PublicKey::deserialize(pk.as_ref()).expect("valid BLS public key");
        Self::from(bytes)
    }

    /// Helper function to convert the public key to the `ethereum_consensus` crate.
    pub(crate) fn to_consensus(&self) -> ethereum_consensus::primitives::BlsPublicKey {
        let bytes = self.compress().serialize();
        ethereum_consensus::primitives::BlsPublicKey::try_from(bytes.as_ref())
            .expect("valid BLS public key")
    }
}

pub(crate) type BlsSignature = bls::Signature;

pub(crate) type Digest = [u8; 32];
