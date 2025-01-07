use serde::Deserialize;

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct Config {
    /// The database connection string URL.
    pub(crate) db_url: String,
}
