use std::collections::HashMap;

use alloy::primitives::Address;
use tokio_stream::StreamExt;
use tracing::info;

use crate::{
    api::spec::RegistryError,
    cli::Config,
    client::BeaconClient,
    db::RegistryDb,
    primitives::{
        registry::{
            DeregistrationBatch, Lookahead, Operator, Registration, RegistrationBatch,
            RegistryEntry,
        },
        BlsPublicKey,
    },
    sources::kapi::KeysApi,
    sync::{SyncHandle, Syncer},
    Action, ActionStream,
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
    Db: RegistryDb,
{
    /// Create a new registry instance.
    pub(crate) fn new(config: Config, db: Db, beacon: BeaconClient) -> Self {
        let kapi = KeysApi::new(&config.keys_api_url);
        // TODO: add health check for the keys API before proceeding

        let (mut syncer, handle) = Syncer::new(config.beacon_url, db.clone());

        // Set source
        syncer.set_source(kapi);

        let _sync_task = syncer.spawn();

        Self { db, beacon, sync: handle }
    }

    /// Handle incoming actions from the API server and update the registry.
    ///
    /// This method will execute until the action stream is closed.
    pub(crate) async fn handle_actions(mut self, mut actions: ActionStream) {
        while let Some(action) = actions.next().await {
            match action {
                Action::Register { registration, response } => {
                    let res = self.register_validators(registration).await;
                    response.send(res).ok();
                }
                Action::Deregister { deregistration, response } => {
                    let res = self.deregister_validators(deregistration).await;
                    response.send(res).ok();
                }
                Action::GetRegistrations { response } => {
                    let res = self.list_registrations().await;
                    response.send(res).ok();
                }
                Action::GetValidators { response } => {
                    let res = self.list_validators().await;
                    response.send(res).ok();
                }
                Action::GetValidatorsByPubkeys { pubkeys, response } => {
                    let res = self.get_validators_by_pubkey(&pubkeys).await;
                    response.send(res).ok();
                }
                Action::GetValidatorsByIndices { indices, response } => {
                    let res = self.get_validators_by_index(indices).await;
                    response.send(res).ok();
                }
                Action::GetValidatorByPubkey { pubkey, response } => {
                    let res = self.get_validators_by_pubkey(&[pubkey]).await;
                    let first_validator_res = res.map(|mut v| v.pop()).transpose();
                    response.send(first_validator_res.unwrap_or(Err(RegistryError::NotFound))).ok();
                }
                Action::GetOperator { signer, response } => {
                    let res = self.get_operators_by_signer(&[signer]).await;
                    let first_operator_res = res.map(|mut o| o.pop()).transpose();
                    response.send(first_operator_res.unwrap_or(Err(RegistryError::NotFound))).ok();
                }
                Action::GetOperators { response } => {
                    let res = self.list_operators().await;
                    response.send(res).ok();
                }
                Action::GetLookahead { epoch, response } => {
                    let res = self.get_lookahead(epoch).await;
                    response.send(res).ok();
                }
            }
        }
    }

    /// Register validators in the registry.
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
            .map(|v| {
                (
                    BlsPublicKey::from_bytes(&v.validator.public_key).expect("valid BLS pubkey"),
                    v.index as u64,
                )
            })
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

    /// Deregister validators from the registry.
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

    /// List all registrations in the registry.
    pub(crate) async fn list_registrations(&mut self) -> Result<Vec<Registration>, RegistryError> {
        self.sync.wait_for_sync().await;
        Ok(self.db.list_registrations().await?)
    }

    /// Get registrations by validator public key.
    pub(crate) async fn get_registrations_by_pubkey(
        &mut self,
        pubkeys: &[BlsPublicKey],
    ) -> Result<Vec<Registration>, RegistryError> {
        self.sync.wait_for_sync().await;
        Ok(self.db.get_registrations_by_pubkey(pubkeys).await?)
    }

    /// List all validators in the registry.
    pub(crate) async fn list_validators(&mut self) -> Result<Vec<RegistryEntry>, RegistryError> {
        self.sync.wait_for_sync().await;
        Ok(self.db.list_validators().await?)
    }

    /// Get validators by validator public key.
    pub(crate) async fn get_validators_by_pubkey(
        &mut self,
        pubkeys: &[BlsPublicKey],
    ) -> Result<Vec<RegistryEntry>, RegistryError> {
        self.sync.wait_for_sync().await;
        Ok(self.db.get_validators_by_pubkey(pubkeys).await?)
    }

    /// Get validators by validator index.
    pub(crate) async fn get_validators_by_index(
        &mut self,
        indices: Vec<u64>,
    ) -> Result<Vec<RegistryEntry>, RegistryError> {
        self.sync.wait_for_sync().await;
        Ok(self.db.get_validators_by_index(indices).await?)
    }

    /// List all operators in the registry.
    pub(crate) async fn list_operators(&mut self) -> Result<Vec<Operator>, RegistryError> {
        self.sync.wait_for_sync().await;
        Ok(self.db.list_operators().await?)
    }

    /// Get operators by signer.
    pub(crate) async fn get_operators_by_signer(
        &mut self,
        signers: &[Address],
    ) -> Result<Vec<Operator>, RegistryError> {
        self.sync.wait_for_sync().await;
        Ok(self.db.get_operators_by_signer(signers).await?)
    }

    /// Get the active validators that will propose in the given epoch
    /// that are also registered in the registry.
    pub(crate) async fn get_lookahead(&mut self, epoch: u64) -> Result<Lookahead, RegistryError> {
        // 1. fetch the proposer duties from the beacon node
        let proposer_duties = self.beacon.get_lookahead(epoch, false).await?;
        let proposer_pubkeys = proposer_duties
            .iter()
            .map(|d| BlsPublicKey::from_bytes(&d.public_key).expect("valid BLS pubkey"))
            .collect::<Vec<_>>();

        // 2. fetch the registry entries from the database
        self.sync.wait_for_sync().await;
        let registry_entries = self.db.get_validators_by_pubkey(&proposer_pubkeys).await?;

        // 3. map registry entries to their proposal slot. example result:
        //
        // 10936976: { validator_pubkey: 0x1234, operator: 0x5678, gas_limit: 1000000, rpc_endpoint: https://rpc.example.com }
        // 10936977: { validator_pubkey: 0x9214, operator: 0x5678, gas_limit: 1000000, rpc_endpoint: https://rpc.example.com }
        // 10936978: { validator_pubkey: 0x1983, operator: 0x5678, gas_limit: 1000000, rpc_endpoint: https://rpc.example.com }
        let mut lookahead = Lookahead::new();
        for duty in proposer_duties {
            let bls_pubkey = BlsPublicKey::from_bytes(&duty.public_key).expect("valid BLS pubkey");
            if let Some(entry) = registry_entries.iter().find(|e| e.validator_pubkey == bls_pubkey)
            {
                lookahead.insert(duty.slot, entry.clone());
            }
        }

        Ok(lookahead)
    }
}
