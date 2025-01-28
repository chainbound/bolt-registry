/// Module defining a beacon chain client for fetching information from the beacon node API.
/// It extends the [`beacon_api_client::mainnet::Client`] with custom error handling and methods.
pub(crate) mod beacon;
pub(crate) use beacon::BeaconClient;
