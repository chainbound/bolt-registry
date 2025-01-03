//! Module `api` contains the API server for the registry. The API server is defined in
//! [`spec::ApiSpec`];

use std::net::SocketAddr;

use actions::{Action, ActionStream};
use tokio::{sync::mpsc, task::JoinHandle};

use crate::primitives::{
    registry::{Deregistration, Lookahead, Operator, Registration, RegistryEntry},
    Address, BlsPublicKey,
};

pub(crate) mod actions;

mod spec;

/// The registry API server, implementing the [`spec::ApiSpec`] trait.
pub(crate) struct RegistryApi {
    cfg: ApiConfig,
    /// Sender notifying event listeners of API events.
    tx: mpsc::Sender<Action>,
}

#[derive(Debug)]
pub(crate) struct ApiConfig {
    listen_addr: SocketAddr,
    action_buffer: usize,
}

impl Default for ApiConfig {
    fn default() -> Self {
        Self { action_buffer: 256, listen_addr: "0.0.0.0:8080".parse().unwrap() }
    }
}

impl RegistryApi {
    pub(crate) fn new(config: ApiConfig) -> (Self, ActionStream) {
        let (tx, rx) = mpsc::channel(config.action_buffer);

        let api = Self { cfg: config, tx };
        let stream = ActionStream::new(rx);

        (api, stream)
    }

    pub(crate) fn spawn(self) -> JoinHandle<()> {
        tokio::spawn(async move {})
    }
}

impl spec::ValidatorSpec for RegistryApi {
    async fn register(&mut self, registration: Registration) -> Result<(), spec::RegistryError> {
        todo!()
    }

    async fn deregister(
        &mut self,
        deregistration: Deregistration,
    ) -> Result<(), spec::RegistryError> {
        todo!()
    }

    async fn get_registrations(&self) -> Result<Vec<Registration>, spec::RegistryError> {
        todo!()
    }
}

impl spec::DiscoverySpec for RegistryApi {
    async fn get_validators(&self) -> Result<Vec<RegistryEntry>, spec::RegistryError> {
        todo!()
    }

    async fn get_validators_by_pubkeys(
        &self,
        pubkeys: Vec<BlsPublicKey>,
    ) -> Result<Vec<RegistryEntry>, spec::RegistryError> {
        todo!()
    }

    async fn get_validators_by_indices(
        &self,
        indices: Vec<usize>,
    ) -> Result<Vec<RegistryEntry>, spec::RegistryError> {
        todo!()
    }

    async fn get_validator_by_pubkey(
        &self,
        pubkey: crate::primitives::BlsPublicKey,
    ) -> Result<RegistryEntry, spec::RegistryError> {
        todo!()
    }

    async fn get_operators(&self) -> Result<Vec<Operator>, spec::RegistryError> {
        todo!()
    }

    async fn get_operator_by_signer(
        &self,
        signer: Address,
    ) -> Result<Operator, spec::RegistryError> {
        todo!()
    }

    async fn get_lookahead(&self, epoch: u64) -> Result<Lookahead, spec::RegistryError> {
        todo!()
    }
}
