use super::{Registration, RegistryDb};

#[derive(Debug, Clone)]
pub(crate) struct NoOpDb;

#[async_trait::async_trait]
impl RegistryDb for NoOpDb {
    async fn register_validators(&self, _registration: Registration) -> sqlx::Result<()> {
        Ok(())
    }
}
