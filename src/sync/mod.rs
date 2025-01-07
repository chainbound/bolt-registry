//! Module `sync` contains functionality for syncing the registry with the chain, and other external
//! data providers.
use tokio::{sync::watch, task::JoinHandle};

use crate::db::RegistryDb;

mod chain;
mod head_tracker;

enum SyncState {
    /// The syncer is currently syncing the registry.
    Syncing,
    /// The syncer is up-to-date.
    Synced,
}

pub(crate) struct SyncHandle {
    state: watch::Receiver<SyncState>,
}

impl SyncHandle {
    /// Returns whether the syncer is currently syncing the registry. If it is, reads should be
    /// blocked until the syncer is done.
    pub(crate) fn is_syncing(&self) -> bool {
        matches!(*self.state.borrow(), SyncState::Syncing)
    }

    /// Resolves when the syncer is done syncing the registry.
    pub(crate) async fn wait_for_sync(&mut self) {
        while !matches!(*self.state.borrow(), SyncState::Synced) {
            // NOTE: we panic here because the whole registry process should fail if the syncer is
            // dropped.
            self.state.changed().await.expect("Syncer dropped, terminating to avoid unsafe state");
        }
    }
}

/// Syncer is responsible for syncing the registry with the operators registry contract and other
/// external data providers.
pub(crate) struct Syncer<Db> {
    db: Db,
    state: watch::Sender<SyncState>,
}

impl<Db: RegistryDb> Syncer<Db> {
    /// Creates a new syncer with the given database.
    pub(crate) fn new(db: Db) -> (Self, SyncHandle) {
        let (state_tx, state_rx) = watch::channel(SyncState::Synced);
        let syncer = Self { db, state: state_tx };
        let handle = SyncHandle { state: state_rx };

        (syncer, handle)
    }

    /// Spawns the [`Syncer`] actor task.
    pub(crate) fn spawn(self) -> JoinHandle<()> {
        tokio::spawn(async move {
            // TODO: handle async logic
        })
    }
}
