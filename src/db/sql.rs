use alloy::primitives::Address;
use sqlx::Postgres;
use tracing::info;

use super::{
    types::{OperatorRow, ValidatorRegistrationRow},
    BlsPublicKey, DbError, DbResult, Operator, Registration, RegistryDb,
};

/// Generic SQL database implementation, that supports all `SQLx` backends.
#[derive(Debug)]
pub(crate) struct SQLDb<Db: sqlx::Database> {
    /// Inner connection pool handled by `SQLx`.
    ///
    /// Cloning `Pool` is cheap as it is simply a
    /// reference-counted handle to the inner pool state.
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

impl RegistryDb for SQLDb<Postgres> {
    async fn register_validators(&self, registration: Registration) -> DbResult<()> {
        if registration.validator_pubkeys.len() != registration.signatures.len() {
            return Err(DbError::Invariant("Mismatched number of pubkeys and signatures"));
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

    async fn register_operator(&self, operator: Operator) -> DbResult<()> {
        sqlx::query(
            "
            INSERT INTO operators (signer, rpc, protocol, source, collateral_tokens, collateral_amounts, last_update)
            VALUES ($1, $2, $3, $4, $5, $6, NOW())
            ",
        )
        .bind(operator.signer.to_vec())
        .bind(operator.rpc_endpoint.to_string())
        .bind("none") // TODO: protocol
        .bind("none") // TODO: source
        // parse arrays as bytea[] with address bytes and little endian u256 bytes
        .bind(operator.collateral_tokens.into_iter().map(|a| a.to_vec()).collect::<Vec<_>>())
        .bind(operator.collateral_amounts.into_iter().map(|a| a.to_le_bytes_vec()).collect::<Vec<_>>())
        .execute(&self.conn)
        .await?;

        Ok(())
    }

    async fn get_operator(&self, signer: Address) -> DbResult<Operator> {
        let row: OperatorRow = sqlx::query_as(
            "
            SELECT signer, rpc, protocol, source, collateral_tokens, collateral_amounts, last_update
            FROM operators
            WHERE signer = $1
            ",
        )
        .bind(signer.to_vec())
        .fetch_one(&self.conn)
        .await?;

        row.try_into()
    }

    async fn get_validator_registration(&self, pubkey: BlsPublicKey) -> DbResult<Registration> {
        let row: ValidatorRegistrationRow = sqlx::query_as(
            "
            SELECT pubkey, signature, expiry, gas_limit, operator, priority, source, last_update
            FROM validator_registrations
            WHERE pubkey = $1
            ",
        )
        .bind(pubkey.serialize().to_vec())
        .fetch_one(&self.conn)
        .await?;

        row.try_into()
    }
}
