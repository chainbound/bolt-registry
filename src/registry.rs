use std::collections::HashMap;

use alloy::primitives::Address;
use tracing::info;

use crate::{
    api::spec::RegistryError,
    cli::Config,
    client::BeaconClient,
    db::RegistryDb,
    primitives::{
        registry::{DeregistrationBatch, Operator, Registration, RegistrationBatch, RegistryEntry},
        BlsPublicKey,
    },
    sources::kapi::KeysApi,
    sync::{SyncHandle, Syncer},
};

/// The main registry object.
pub(crate) struct Registry<Db> {
    /// The database handle.
    db: Db,
    /// The beacon API client.
    beacon: BeaconClient,
    /// Handle to the syncer. The implementation MUST block any DB reads & writes
    /// until the syncer is done syncing the registry.
    sync: SyncHandle,
}

impl<Db> Registry<Db>
where
    Db: RegistryDb + Send + Clone + 'static,
{
    pub(crate) fn new(config: Config, db: Db, beacon: BeaconClient) -> Self {
        let kapi = KeysApi::new(&config.keys_api_url);
        // TODO: add health check for the keys API before proceeding

        let (mut syncer, handle) = Syncer::new(&config.beacon_url, db.clone());

        // Set source
        syncer.set_source(kapi);

        let _sync_task = syncer.spawn();

        Self { db, beacon, sync: handle }
    }

    pub(crate) async fn register_validators(
        &mut self,
        registration: RegistrationBatch,
    ) -> Result<(), RegistryError> {
        let count = registration.validator_pubkeys.len();
        let operator = registration.operator;

        // 1. validate the existence and activity of the validators in the beacon chain
        let pubkeys = registration.validator_pubkeys.as_slice();
        let validators = self.beacon.get_active_validators_by_pubkey(pubkeys).await?;

        // 2. collect a map of validator public keys to their indices
        let index_map = validators
            .into_iter()
            .map(|v| (BlsPublicKey::from_consensus(v.validator.public_key), v.index))
            .collect::<HashMap<_, _>>();

        // 3. check that all validators are present
        if index_map.len() != count {
            return Err(RegistryError::BadRequest(
                "Not all validators are active in the beacon chain, skipping registration",
            ));
        }

        // 4. insert the registrations into the database
        let registrations = registration.into_items(index_map);

        self.sync.wait_for_sync().await;
        self.db.register_validators(&registrations).await?;

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
