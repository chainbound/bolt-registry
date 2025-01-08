use clap::Parser;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, Parser)]
pub(crate) struct Config {
    /// The database connection string URL.
    #[clap(long, env = "DB_URL")]
    pub(crate) db_url: String,
}
