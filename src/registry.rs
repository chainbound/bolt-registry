use tracing::info;

use crate::{
    api::spec::RegistryError,
    cli::Config,
    db::RegistryDb,
    primitives::registry::Registration,
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
        &self,
        registration: Registration,
    ) -> Result<(), RegistryError> {
        let count = registration.validator_pubkeys.len();
        let operator = registration.operator;

        self.db.register_validators(registration).await?;
        info!(%count, %operator, "Validators registered successfully");

        Ok(())
    }
}
