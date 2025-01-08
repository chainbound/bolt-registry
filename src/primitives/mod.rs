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

    /// Creates a new `BlsPublicKey` from a compressed byte slice.
    pub(crate) fn from_bytes(bytes: &[u8]) -> Result<Self, bls::Error> {
        Ok(Self(bls::PublicKey::deserialize(bytes)?))
    }
}

pub(crate) type BlsSignature = bls::Signature;

pub(crate) type Digest = [u8; 32];
