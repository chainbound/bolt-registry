use clap::Parser;
use serde::{Deserialize, Serialize};

/// The main configuration for the bolt registry server.
#[derive(Debug, Clone, Serialize, Deserialize, Parser)]
pub(crate) struct Config {
    /// The database connection string URL.
    #[clap(long, env = "DB_URL")]
    pub(crate) db_url: String,
    /// The URL of the remote beacon node.
    #[clap(long, env = "BEACON_URL")]
    pub(crate) beacon_url: String,
}
