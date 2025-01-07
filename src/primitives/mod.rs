use derive_more::derive::{Deref, DerefMut, From};
use serde::{Deserialize, Serialize};

pub(crate) mod registry;

#[derive(Debug, Clone, Serialize, Deserialize, Deref, DerefMut, From)]
pub(crate) struct BlsPublicKey(bls::PublicKey);

impl BlsPublicKey {
    #[cfg(test)]
    pub(crate) fn random() -> Self {
        Self(bls::Keypair::random().pk)
    }
}

pub(crate) type BlsSignature = bls::Signature;

pub(crate) type Digest = [u8; 32];
