use alloy::primitives::Address;
use tracing::info;

use crate::{
    api::spec::RegistryError,
    cli::Config,
    db::RegistryDb,
    primitives::{
        registry::{DeregistrationBatch, Operator, Registration, RegistrationBatch, RegistryEntry},
        BlsPublicKey,
    },
    sync::{SyncHandle, Syncer},
};

/// The main registry object.
pub(crate) struct Registry<Db> {
    /// The database handle.
    db: Db,
    /// Handle to the syncer. Before any reads, the implementation MUST block any reads & writes
    /// until the syncer is done syncing the registry.
    sync: SyncHandle,
}

impl<Db: RegistryDb> Registry<Db> {
    pub(crate) fn new(config: Config, db: Db) -> Self {
        let (syncer, handle) = Syncer::new(&config.beacon_url, db.clone());

        let _sync_task = syncer.spawn();

        Self { db, sync: handle }
    }

    pub(crate) async fn register_validators(
        &mut self,
        registration: RegistrationBatch,
    ) -> Result<(), RegistryError> {
        let count = registration.validator_pubkeys.len();
        let operator = registration.operator;

        self.sync.wait_for_sync().await;
        self.db.register_validators(&registration.into_items()).await?;

        info!(%count, %operator, "Validators registered successfully");
        Ok(())
    }

    pub(crate) async fn deregister_validators(
        &mut self,
        deregistration: DeregistrationBatch,
    ) -> Result<(), RegistryError> {
        let count = deregistration.validator_pubkeys.len();
        let operator = deregistration.operator;

        self.sync.wait_for_sync().await;
        self.db.deregister_validators(&deregistration.into_items()).await?;

        info!(%count, %operator, "Validators deregistered successfully");
        Ok(())
    }

    pub(crate) async fn list_registrations(&mut self) -> Result<Vec<Registration>, RegistryError> {
        self.sync.wait_for_sync().await;
        Ok(self.db.list_registrations().await?)
    }

    pub(crate) async fn get_registrations_by_pubkey(
        &mut self,
        pubkeys: &[BlsPublicKey],
    ) -> Result<Vec<Registration>, RegistryError> {
        self.sync.wait_for_sync().await;
        Ok(self.db.get_registrations_by_pubkey(pubkeys).await?)
    }

    pub(crate) async fn list_validators(&mut self) -> Result<Vec<RegistryEntry>, RegistryError> {
        self.sync.wait_for_sync().await;
        Ok(self.db.list_validators().await?)
    }

    pub(crate) async fn get_validators_by_pubkey(
        &mut self,
        pubkeys: &[BlsPublicKey],
    ) -> Result<Vec<RegistryEntry>, RegistryError> {
        self.sync.wait_for_sync().await;
        Ok(self.db.get_validators_by_pubkey(pubkeys).await?)
    }

    pub(crate) async fn get_validators_by_index(
        &mut self,
        indices: Vec<usize>,
    ) -> Result<Vec<RegistryEntry>, RegistryError> {
        self.sync.wait_for_sync().await;
        Ok(self.db.get_validators_by_index(indices).await?)
    }

    pub(crate) async fn list_operators(&mut self) -> Result<Vec<Operator>, RegistryError> {
        self.sync.wait_for_sync().await;
        Ok(self.db.list_operators().await?)
    }

    pub(crate) async fn get_operators_by_signer(
        &mut self,
        signers: &[Address],
    ) -> Result<Vec<Operator>, RegistryError> {
        self.sync.wait_for_sync().await;
        Ok(self.db.get_operators_by_signer(signers).await?)
    }
}
