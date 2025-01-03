//! Module `db` contains database related traits and implementations, with registry-specific
//! abstractions.

/// Registry database trait.
pub(crate) trait RegistryDb {}

#[derive(Debug, Clone)]
pub(crate) struct DummyDb;

impl RegistryDb for DummyDb {}
