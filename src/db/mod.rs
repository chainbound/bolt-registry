//! Module `db` contains database related traits and implementations, with registry-specific
//! abstractions.

mod noop;
pub(crate) use noop::NoOpDb;

use tracing::info;

/// Registry database trait.
#[async_trait::async_trait]
pub(crate) trait RegistryDb: Clone {}

/// Generic SQL database implementation.
#[derive(Debug)]
pub(crate) struct SQLDb<Db: sqlx::Database> {
    conn: sqlx::Pool<Db>,
}

impl SQLDb<sqlx::Postgres> {
    /// Create a new Postgres database connection, and run DDL queries.
    pub(crate) async fn new_pg(url: &str) -> Result<Self, sqlx::Error> {
        let conn = sqlx::postgres::PgPoolOptions::new().max_connections(10).connect(url).await?;
        let this = Self { conn };

        this.pg_ddl().await?;

        Ok(this)
    }

    /// Run DDL queries for Postgres.
    async fn pg_ddl(&self) -> Result<(), sqlx::Error> {
        let ddl = include_str!("./sql/pg_ddl.sql");
        sqlx::raw_sql(ddl).execute(&self.conn).await?;
        info!("Postgres DDL queries executed successfully");

        Ok(())
    }
}

// Manual clone implementation is required for satisfying the `RegistryDb` trait bound.
// Deriving `Clone` on `SQLDb` is not enough because of the generic type parameter.
impl<Db: sqlx::Database> Clone for SQLDb<Db> {
    fn clone(&self) -> Self {
        Self { conn: self.conn.clone() }
    }
}

impl<Db: sqlx::Database> RegistryDb for SQLDb<Db> {}
