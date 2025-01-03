use std::ops::{Deref, DerefMut};

use serde::{Deserialize, Serialize};

// re-export primitives from alloy
pub(crate) use alloy::primitives::*;

pub(crate) mod registry;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct BlsPublicKey(bls::PublicKey);

impl Deref for BlsPublicKey {
    type Target = bls::PublicKey;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl DerefMut for BlsPublicKey {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.0
    }
}

impl BlsPublicKey {
    #[cfg(test)]
    pub(crate) fn random() -> Self {
        Self(bls::Keypair::random().pk)
    }
}

pub(crate) type BlsSignature = bls::Signature;
