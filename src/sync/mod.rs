//! Module `sync` contains functionality for syncing the registry with the chain, and other external
//! data providers.
use chain::{BeaconClient, EpochTransition, EpochTransitionStream};
use reqwest::IntoUrl;
use thiserror::Error;
use tokio::{sync::watch, task::JoinHandle};
use tokio_stream::StreamExt;
use tracing::info;

use crate::db::RegistryDb;

mod chain;

#[derive(Debug, Error)]
pub(crate) enum SyncError {
    #[error(transparent)]
    Beacon(#[from] beacon_api_client::Error),
}

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
    events_client: BeaconClient,
}

impl<Db> Syncer<Db>
where
    Db: RegistryDb + Send + 'static,
{
    /// Creates a new syncer with the given database.
    pub(crate) fn new(beacon_url: impl IntoUrl, db: Db) -> (Self, SyncHandle) {
        let (state_tx, state_rx) = watch::channel(SyncState::Synced);
        let handle = SyncHandle { state: state_rx };

        let events_client = BeaconClient::new(beacon_url);

        let syncer = Self { db, state: state_tx, events_client };

        (syncer, handle)
    }

    /// Spawns the [`Syncer`] actor task.
    pub(crate) fn spawn(mut self) -> JoinHandle<Result<(), SyncError>> {
        tokio::spawn(async move {
            let pa_stream = self.events_client.subscribe_payload_attributes().await?;

            let mut epoch_stream = EpochTransitionStream::new(pa_stream);

            while let Some(transition) = epoch_stream.next().await {
                self.on_transition(transition);
            }

            Ok(())
        })
    }

    /// Handles an epoch transition event.
    fn on_transition(&mut self, transition: EpochTransition) {
        info!(
            epoch = transition.epoch,
            slot = transition.slot,
            block_number = transition.block_number,
            "New epoch transition"
        );

        // Update to syncing state
        let _ = self.state.send(SyncState::Syncing);
    }
}
