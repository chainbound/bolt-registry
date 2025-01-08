use serde::{Deserialize, Serialize};

/// The main configuration for the bolt registry server.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct Config {
    /// The database connection string URL.
    pub(crate) db_url: String,
    /// The URL of the remote beacon node.
    pub(crate) beacon_url: String,
    /// The URL of the keys API.
    pub(crate) keys_api_url: String,
}
