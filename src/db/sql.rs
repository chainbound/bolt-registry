use sqlx::Postgres;
use tracing::info;

use super::{Registration, RegistryDb};

/// Generic SQL database implementation, that supports all `SQLx` backends.
#[derive(Debug)]
pub(crate) struct SQLDb<Db: sqlx::Database> {
    conn: sqlx::Pool<Db>,
}

impl SQLDb<sqlx::Postgres> {
    /// Create a new Postgres database connection, and run DDL queries.
    pub(crate) async fn new(url: &str) -> Result<Self, sqlx::Error> {
        let conn = sqlx::postgres::PgPoolOptions::new().max_connections(10).connect(url).await?;
        let this = Self { conn };

        this.ddl().await?;

        Ok(this)
    }

    /// Run DDL queries for Postgres.
    async fn ddl(&self) -> Result<(), sqlx::Error> {
        sqlx::raw_sql(include_str!("./sql/pg_ddl.sql")).execute(&self.conn).await?;
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

#[async_trait::async_trait]
impl RegistryDb for SQLDb<Postgres> {
    async fn register_validators(&self, registration: Registration) -> sqlx::Result<()> {
        if registration.validator_pubkeys.len() != registration.signatures.len() {
            return Err(sqlx::Error::Protocol("Mismatched number of pubkeys and signatures".into()));
        }

        let mut transaction = self.conn.begin().await?;

        for (pubkey, signature) in
            registration.validator_pubkeys.iter().zip(&registration.signatures)
        {
            sqlx::query(
                "
                INSERT INTO validator_registrations (pubkey, signature, expiry, operator, priority, source, last_update)
                VALUES ($1, $2, $3, $4, $5, $6, NOW())
                "
            )
            .bind(pubkey.serialize())
            .bind(signature.serialize())
            .bind(registration.expiry.to_string())
            .bind(registration.operator.to_vec())
            .bind(0) // TODO: priority
            .bind("none") // TODO: source
            .execute(&mut *transaction).await?;
        }

        transaction.commit().await?;

        Ok(())
    }
}
