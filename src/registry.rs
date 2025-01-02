use crate::db::RegistryDb;

/// The main registry object.
pub(crate) struct Registry<Db> {
    db: Db,
}

impl<Db: RegistryDb> Registry<Db> {
    pub(crate) const fn new(db: Db) -> Self {
        Self { db }
    }
}
