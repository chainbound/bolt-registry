use crate::{
    db::RegistryDb,
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

impl<Db: RegistryDb + Clone> Registry<Db> {
    pub(crate) fn new(db: Db) -> Self {
        let (syncer, handle) = Syncer::new(db.clone());

        syncer.spawn();

        Self { db, sync: handle }
    }
}
