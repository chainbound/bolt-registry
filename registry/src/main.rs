#![doc = include_str!("../README.md")]
#![warn(missing_debug_implementations, missing_docs, rustdoc::all)]
#![deny(unused_must_use, rust_2018_idioms)]
#![cfg_attr(docsrs, feature(doc_cfg, doc_auto_cfg))]

//! Entrypoint for the registry server binary.

use eyre::bail;
use tracing::{info, warn};

/// API server for the registry, implemented by [`RegistryApi`].
/// Contains all the API spec, routes, docs and handlers.
mod api;
use api::{
    actions::{Action, ActionStream},
    ApiConfig, RegistryApi,
};

/// Various extendable client implementations to communicate
/// with external services such as Ethereum nodes.
mod client;
use client::BeaconClient;

/// Chain input-output interfaces and abstractions.
mod chainio;

/// Database backends.
mod db;
use db::{InMemoryDb, SQLDb};

/// Primitive types and data structures.    
mod primitives;

/// The main registry server implementation.
mod registry;
use registry::Registry;

/// Sources of actions to process.
mod sources;

/// Syncing logic.
mod sync;

/// CLI and configuration.
mod cli;

#[tokio::main]
async fn main() -> eyre::Result<()> {
    tracing_subscriber::fmt::init();

    info!("Starting bolt registry server...");

    let config = cli::Opts::parse_config()?;
    let beacon = BeaconClient::new(config.beacon_url.clone());

    let (srv, actions) = RegistryApi::new(ApiConfig::default());

    if let Err(e) = srv.spawn().await {
        bail!("Failed to start API server: {}", e);
    }

    // Initialize the registry with the specified database backend.
    //
    // * If a database URL is provided, use the SQL database backend.
    // * Otherwise, use the in-memory cache backend.
    if let Some(ref db_url) = config.db_url {
        info!("Using PostgreSQL database backend");
        let db = SQLDb::new(db_url).await?;

        Registry::new(config, db, beacon).handle_actions(actions).await;
    } else {
        info!("Using In-memory database backend");
        let db = InMemoryDb::default();

        Registry::new(config, db, beacon).handle_actions(actions).await;
    }

    warn!("Action stream closed, shutting down...");
    Ok(())
}
