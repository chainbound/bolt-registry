use crate::{
    db::RegistryDb,
    sync::{SyncHandle, Syncer},
};

/// The main registry object.
pub(crate) struct Registry<Db> {
    db: Db,
    sync: SyncHandle,
}

impl<Db: RegistryDb + Clone> Registry<Db> {
    pub(crate) fn new(db: Db) -> Self {
        let (syncer, handle) = Syncer::new(db.clone());

        syncer.spawn();

        Self { db, sync: handle }
    }
}
