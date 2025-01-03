//! The API specification for the registry, and its errors. Contains 2 sub-specs: [`ValidatorSpec`]
//! and [`DiscoverySpec`]. The [`ApiSpec`] trait combines both of these.
use thiserror::Error;

use crate::primitives::{
    registry::{Deregistration, Lookahead, Operator, Registration, RegistryEntry},
    Address, BlsPublicKey,
};

pub(super) const VALIDATORS_REGISTER_PATH: &str = "/registry/v1/validators/register";
pub(super) const VALIDATORS_DEREGISTER_PATH: &str = "/registry/v1/validators/deregister";
pub(super) const VALIDATORS_REGISTRATIONS_PATH: &str = "/registry/v1/validators/registrations";
pub(super) const DISCOVERY_VALIDATORS_PATH: &str = "/registry/v1/discovery/validators";
pub(super) const DISCOVERY_VALIDATOR_PATH: &str = "/registry/v1/discovery/validators/:pubkey";
pub(super) const DISCOVERY_OPERATORS_PATH: &str = "/registry/v1/discovery/operators";
pub(super) const DISCOVERY_OPERATOR_PATH: &str = "/registry/v1/discovery/operators/:signer";
pub(super) const DISCOVERY_LOOKAHEAD_PATH: &str = "/registry/v1/discovery/lookahead/:epoch";

/// The registry API spec for validators.
pub(super) trait ValidatorSpec {
    /// /registry/v1/validators/register
    async fn register(&self, registration: Registration) -> Result<(), RegistryError>;

    /// /registry/v1/validators/deregister
    async fn deregister(&self, deregistration: Deregistration) -> Result<(), RegistryError>;

    /// /registry/v1/validators/registrations
    async fn get_registrations(&self) -> Result<Vec<Registration>, RegistryError>;
}

/// The registry API spec for discovery.
pub(super) trait DiscoverySpec {
    /// /registry/v1/discovery/validators
    async fn get_validators(&self) -> Result<Vec<RegistryEntry>, RegistryError>;

    /// /registry/v1/discovery/validators?pubkeys=...
    async fn get_validators_by_pubkeys(
        &self,
        pubkeys: Vec<BlsPublicKey>,
    ) -> Result<Vec<RegistryEntry>, RegistryError>;

    /// /registry/v1/discovery/validators?indices=...
    async fn get_validators_by_indices(
        &self,
        indices: Vec<usize>,
    ) -> Result<Vec<RegistryEntry>, RegistryError>;

    /// /registry/v1/discovery/validators/{pubkey}
    async fn get_validator_by_pubkey(
        &self,
        pubkey: BlsPublicKey,
    ) -> Result<RegistryEntry, RegistryError>;

    /// /registry/v1/discovery/operators
    async fn get_operators(&self) -> Result<Vec<Operator>, RegistryError>;

    /// /registry/v1/discovery/operators/{signer}
    async fn get_operator_by_signer(&self, signer: Address) -> Result<Operator, RegistryError>;

    /// /registry/v1/discovery/lookahead/{epoch}
    /// This will return `TooEarly` if the epoch is too far in the future.
    async fn get_lookahead(&self, epoch: u64) -> Result<Lookahead, RegistryError>;
}

/// The registry API specification.
pub(super) trait ApiSpec: ValidatorSpec + DiscoverySpec {}

#[derive(Debug, Error)]
pub(crate) enum RegistryError {}
