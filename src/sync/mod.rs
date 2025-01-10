//! Module `sync` contains functionality for syncing the registry with the chain, and other external
//! data providers.
use std::collections::HashMap;

use beacon_api_client::ProposerDuty;
use chain::{EpochTransition, EpochTransitionStream};
use reqwest::IntoUrl;
use thiserror::Error;
use tokio::{sync::watch, task::JoinHandle};
use tokio_stream::StreamExt;
use tracing::{error, info};

use crate::{
    client::{beacon::BeaconClientError, BeaconClient},
    db::RegistryDb,
    primitives::{
        registry::{Operator, Registration},
        BlsPublicKey, SyncStateUpdate,
    },
    sources::ExternalSource,
};

mod chain;

#[derive(Debug, Error)]
pub(crate) enum SyncError {
    #[error(transparent)]
    Beacon(#[from] BeaconClientError),
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

    /// External data source.
    /// NOTE: We use dynamic dispatch because when we have multiple data sources, we don't want to
    /// have to change the `Syncer` struct every time we add a new source. This will all sit in a
    /// vector of sources.
    source: Option<Box<dyn ExternalSource + Send + Sync>>,

    /// The last known block number. Whenever a new epoch transition occurs, sync contract events
    /// from this block number to the new block number.
    last_block_number: u64,
    /// The last known epoch number. Whenever a new epoch transition occurs, sync all lookaheads
    /// from this epoch to the new epoch.
    last_epoch: u64,
}

impl<Db> Syncer<Db>
where
    Db: RegistryDb + Send + Sync + 'static,
{
    /// Creates a new syncer with the given beacon and keys API URLs, and the database handle.
    pub(crate) fn new(beacon_url: impl IntoUrl, db: Db) -> (Self, SyncHandle) {
        let (state_tx, state_rx) = watch::channel(SyncState::Synced);
        let handle = SyncHandle { state: state_rx };

        let beacon_client = BeaconClient::new(beacon_url.into_url().unwrap());

        // TODO: read the last block number from the database and use as checkpoint for backfill
        let syncer = Self {
            db,
            state: state_tx,
            beacon_client,
            source: None,
            last_block_number: 0,
            last_epoch: 0,
        };

        (syncer, handle)
    }

    /// Sets an external data source.
    pub(crate) fn set_source<S: ExternalSource + Send + Sync + 'static>(&mut self, source: S) {
        self.source = Some(Box::new(source));
    }

    pub(crate) fn set_last_epoch(&mut self, epoch: u64) {
        self.last_epoch = epoch;
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

    /// Handles an epoch transition event.
    async fn on_transition(&mut self, transition: EpochTransition) {
        let start = std::time::Instant::now();
        info!(
            epoch = transition.epoch,
            slot = transition.slot,
            block_number = transition.block_number,
            "New epoch transition"
        );

        // Update to syncing state
        let _ = self.state.send(SyncState::Syncing);

        self.sync_contract_events(transition.block_number).await;

        // Sync from the last known epoch to the new epoch
        for epoch in self.last_epoch..=transition.epoch {
            // TODO: handle failure here (currently infinitely retried inside beacon_client)
            let Ok(lookahead) = self.beacon_client.get_lookahead(epoch, true).await else {
                error!("Failed to get lookahead for epoch {}", transition.epoch);
                return;
            };

            self.sync_lookahead(lookahead).await;
        }

        // Update last epoch
        self.last_epoch = transition.epoch;

        // Update the sync state in the database
        // TODO: retries on transient faults (e.g. network errors)
        // TODO: ideally all DB operation in an epoch transition need to be made
        // in a single transaction to avoid partial updates in case of failure
        if let Err(e) = self.db.update_sync_state(SyncStateUpdate::from(transition)).await {
            error!(error = ?e, "Failed to update sync state in the database");
        }

        info!(elapsed = ?start.elapsed(), "Transition handled");
        let _ = self.state.send(SyncState::Synced);
    }

    /// Syncs contract events from the last known block number to the given block number.
    async fn sync_contract_events(&self, block_number: u64) {
        // TODO:
        // 1. Get contract logs from self.last_block_number to block_number
        // 2. Sync to database
        // 3. Update last_block_number = block_number
    }

    /// Syncs the lookahead with external data sources.
    async fn sync_lookahead(&self, lookahead: Vec<ProposerDuty>) {
        let pubkeys = lookahead
            .into_iter()
            .map(|duty| {
                BlsPublicKey::from_bytes(&duty.public_key).expect("failed to parse public key")
            })
            .collect::<Vec<_>>();

        let start = std::time::Instant::now();

        let Some(source) = self.source.as_ref() else {
            info!("No external source configured, skipping...");
            return;
        };

        let mut entries = loop {
            match source.get_validators(&pubkeys).await {
                Ok(registrations) => break registrations,
                Err(e) => {
                    error!(error = ?e, "Failed to get validators from {}, retrying...", source.name());
                    tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;
                }
            }
        };

        let pubkeys =
            entries.iter().map(|entry| entry.validator_pubkey.clone()).collect::<Vec<_>>();

        info!(count = entries.len(), elapsed = ?start.elapsed(), "Queried entries from {}", source.name());

        let Ok(summaries) = self.beacon_client.get_active_validator_summaries(&pubkeys).await
        else {
            error!("Failed to get active validator summaries from the beacon chain");
            return
        };

        // Remove entries that are not present in the beacon chain
        entries.retain(|entry| {
            if !summaries.iter().any(|summary| {
                summary.validator.public_key == entry.validator_pubkey.to_consensus()
            }) {
                error!(
                    "Validator not found / active in the beacon chain: {:?}",
                    entry.validator_pubkey
                );
                return false;
            }

            true
        });

        let mut operators = HashMap::new();

        let registrations = entries
            .into_iter()
            .map(|entry| {
                let validator_index = summaries
                    .iter()
                    .find(|s| s.validator.public_key == entry.validator_pubkey.to_consensus())
                    .map(|s| s.index as u64)
                    .expect("validator summary is present");

                let operator = Operator {
                    signer: entry.operator,
                    rpc_endpoint: entry.rpc_endpoint,
                    // TODO: once collateral is supported, update this
                    collateral_tokens: vec![],
                    collateral_amounts: vec![],
                };

                operators.insert(entry.operator, operator);

                Registration {
                    validator_pubkey: entry.validator_pubkey,
                    operator: entry.operator,
                    gas_limit: 10_000,
                    expiry: 0,
                    validator_index,
                    signature: None,
                }
            })
            .collect::<Vec<_>>();

        // TODO: retries on transient faults (e.g. network errors)
        // TODO: use a DB transaction here
        if let Err(e) = self.db.register_validators(&registrations).await {
            error!(error = ?e, "Failed to register validators in the database");
        }

        for operator in operators.into_values() {
            if let Err(e) = self.db.register_operator(operator).await {
                error!(error = ?e, "Failed to register operator in the database");
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use alloy::primitives::Address;

    use crate::{db::InMemoryDb, primitives::registry::RegistryEntry, sources::mock::MockSource};

    use super::*;

    #[tokio::test]
    async fn test_external_source_sync() -> eyre::Result<()> {
        let _ = tracing_subscriber::fmt().with_max_level(tracing::Level::INFO).try_init();

        let Ok(beacon_url) = std::env::var("BEACON_URL") else {
            tracing::warn!("Skipping test because of missing BEACON_URL");
            return Ok(())
        };

        let db = InMemoryDb::default();
        let (mut syncer, mut handle) = Syncer::new(beacon_url, db.clone());

        let mut source = MockSource::new();

        // Get current epoch and lookahead
        let epoch = syncer.beacon_client.get_epoch().await?;
        let lookahead = syncer.beacon_client.get_lookahead(epoch, true).await?;

        let pubkey = lookahead.first().unwrap().public_key.clone();
        let pubkey = BlsPublicKey::from_bytes(&pubkey).unwrap();

        let operator = Address::default();

        for duty in lookahead {
            let entry = RegistryEntry {
                validator_pubkey: BlsPublicKey::from_bytes(&duty.public_key).unwrap(),
                operator,
                gas_limit: 0,
                rpc_endpoint: "https://rick.com".parse().unwrap(),
            };

            source.add_entry(entry);
        }

        // Make sure we don't sync from scatch
        syncer.set_last_epoch(epoch - 1);

        syncer.set_source(source);
        syncer.spawn();

        // Wait for state to change to `Syncing`
        handle.state.changed().await.unwrap();
        // Wait for syncing to complete
        handle.wait_for_sync().await;

        // Check validator registration
        assert!(!db.get_validators_by_pubkey(&[pubkey.clone()]).await?.is_empty());
        assert!(!db.get_operators_by_signer(&[operator]).await?.is_empty());

        Ok(())
    }
}
