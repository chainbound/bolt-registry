use super::RegistryDb;

#[derive(Debug, Clone)]
pub(crate) struct NoOpDb;

impl RegistryDb for NoOpDb {}
