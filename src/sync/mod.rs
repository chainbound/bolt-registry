//! Module `sync` contains functionality for syncing the registry with the chain, and other external
//! data providers.

use std::sync::{Arc, Mutex};

use tokio::sync::watch;

enum SyncState {
    /// The syncer is currently syncing the registry.
    Syncing,
    /// The syncer is up-to-date.
    Synced,
}

struct SyncHandle {
    state: watch::Receiver<SyncState>,
}

impl SyncHandle {
    /// Returns whether the syncer is currently syncing the registry. If it is, reads should be
    /// blocked until the syncer is done.
    pub(crate) fn is_syncing(&self) -> bool {
        matches!(*self.state.borrow(), SyncState::Syncing)
    }

    pub(crate) async fn wait_for_sync(&mut self) {
        while !matches!(*self.state.borrow(), SyncState::Synced) {
            // NOTE: we panic here because the registry should fail if the syncer is dropped.
            self.state.changed().await.expect("Syncer dropped");
        }
    }
}

/// Syncer is responsible for syncing the registry with the operators registry contract and other
/// external data providers.
struct Syncer<Db> {
    db: Db,
    state: watch::Sender<SyncState>,
}
