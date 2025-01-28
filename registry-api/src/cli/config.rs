use serde::{Deserialize, Serialize};
use url::Url;

/// The main configuration for the bolt registry server.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct Config {
    /// The database (Postgres) connection string URL.
    ///
    /// When not provided, the server will use an in-memory database.
    pub(crate) db_url: Option<String>,
    /// The URL of the remote Ethereum beacon node HTTP API.
    pub(crate) beacon_url: Url,
    /// The URL of the Lido "keys API".
    pub(crate) keys_api_url: String,
}
