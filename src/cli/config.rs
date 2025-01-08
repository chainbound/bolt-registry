use clap::Parser;
use serde::Deserialize;

#[derive(Debug, Clone, Deserialize, Parser)]
pub(crate) struct Config {
    /// The database connection string URL.
    #[clap(long, env = "DB_URL")]
    pub(crate) db_url: String,
}
