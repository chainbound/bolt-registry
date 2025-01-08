//! Module `sync` contains functionality for syncing the registry with the chain, and other external
//! data providers.
use beacon_client::ProposerDuty;
use chain::{BeaconClient, EpochTransition, EpochTransitionStream};
use reqwest::IntoUrl;
use thiserror::Error;
use tokio::{sync::watch, task::JoinHandle};
use tokio_stream::StreamExt;
use tracing::{error, info};

use crate::{db::RegistryDb, sources::kapi::KeysApi};

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
    beacon_client: BeaconClient,

    /// Lido keys API.
    keys_api: KeysApi,

    /// The last known block number. Whenever a new epoch transition occurs, sync contract events
    /// from this block number to the new block number.
    last_block_number: u64,
}

impl<Db> Syncer<Db>
where
    Db: RegistryDb + Send + 'static,
{
    /// Creates a new syncer with the given beacon and keys API URLs, and the database handle.
    pub(crate) fn new(
        beacon_url: impl IntoUrl,
        keys_api: impl IntoUrl,
        db: Db,
    ) -> (Self, SyncHandle) {
        let (state_tx, state_rx) = watch::channel(SyncState::Synced);
        let handle = SyncHandle { state: state_rx };

        let beacon_client = BeaconClient::new(beacon_url);
        let kapi = KeysApi::new(keys_api);

        // TODO: read the last block number from the database and use as checkpoint for backfill
        let syncer =
            Self { db, state: state_tx, beacon_client, keys_api: kapi, last_block_number: 0 };

        (syncer, handle)
    }

    /// Spawns the [`Syncer`] actor task.
    pub(crate) fn spawn(mut self) -> JoinHandle<Result<(), SyncError>> {
        tokio::spawn(async move {
            let pa_stream = self.beacon_client.subscribe_payload_attributes().await?;

            let mut epoch_stream = EpochTransitionStream::new(pa_stream);

            while let Some(transition) = epoch_stream.next().await {
                self.on_transition(transition).await;
            }

            Ok(())
        })
    }

    /// Backfills the registry from the last known block number to the current block number.
    async fn backfill(&mut self) {
        todo!()
    }

    /// Handles an epoch transition event.
    async fn on_transition(&mut self, transition: EpochTransition) {
        info!(
            epoch = transition.epoch,
            slot = transition.slot,
            block_number = transition.block_number,
            "New epoch transition"
        );

        // Update to syncing state
        let _ = self.state.send(SyncState::Syncing);

        self.sync_contract_events(transition.block_number).await;

        // TODO: handle failure here (currently infinitely retried inside beacon_client)
        let Ok(lookahead) = self.beacon_client.get_lookahead(transition.epoch, true).await else {
            error!("Failed to get lookahead for epoch {}", transition.epoch);
            return;
        };

        self.sync_lookahead(lookahead).await;
    }

    /// Syncs contract events from the last known block number to the given block number.
    async fn sync_contract_events(&mut self, block_number: u64) {
        // 1. Get contract logs from self.last_block_number to block_number
        // 2. Sync to database
        // 3. Update last_block_number = block_number
        todo!()
    }

    async fn sync_lookahead(&mut self, lookahead: Vec<ProposerDuty>) {
        todo!()
    }
}
