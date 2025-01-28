use std::sync::{atomic::AtomicU64, Arc};

use alloy::primitives::Address;
use sqlx::Postgres;
use tracing::{debug, info};

use super::{
    types::{OperatorRow, ValidatorRegistrationRow},
    BlsPublicKey, DbResult, Deregistration, Operator, Registration, RegistryDb, RegistryEntry,
    SyncStateUpdate, SyncTransaction,
};

/// Generic SQL database implementation, that supports all `SQLx` backends.
#[derive(Debug)]
pub(crate) struct SQLDb<Db: sqlx::Database> {
    /// Inner connection pool handled by `SQLx`.
    ///
    /// Cloning `Pool` is cheap as it is simply a
    /// reference-counted handle to the inner pool state.
    conn: sqlx::Pool<Db>,
    /// ID counter for transactions.
    next_id: Arc<AtomicU64>,
}

impl SQLDb<sqlx::Postgres> {
    /// Create a new Postgres database connection, and run DDL queries.
    pub(crate) async fn new(url: &str) -> Result<Self, sqlx::Error> {
        let conn = sqlx::postgres::PgPoolOptions::new().max_connections(10).connect(url).await?;
        let this = Self { conn, next_id: Default::default() };

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
        Self { conn: self.conn.clone(), next_id: Arc::clone(&self.next_id) }
    }
}

pub(crate) struct SQLSyncTransaction {
    id: u64,
    transaction: sqlx::Transaction<'static, Postgres>,
}

#[async_trait::async_trait]
impl SyncTransaction for SQLSyncTransaction {
    async fn register_validators(&mut self, registrations: &[Registration]) -> DbResult<()> {
        let mut rows_affected = 0;
        for registration in registrations {
            let result = sqlx::query(
                "
                INSERT INTO validator_registrations (pubkey, index, signature, expiry, operator, priority, source, last_update)
                VALUES ($1, $2, $3, $4, $5, $6, $7, NOW())
                "
            )
            .bind(registration.validator_pubkey.serialize())
            .bind(registration.validator_index as i64)
            .bind(registration.signature.as_ref().map(|s| s.serialize()))
            .bind(registration.expiry.to_string())
            .bind(registration.operator.to_vec())
            .bind(0) // TODO: priority
            .bind("none") // TODO: source
            .execute(&mut *self.transaction).await?.rows_affected();

            rows_affected += result;
        }

        debug!(transaction_id = self.id, rows_affected, "register_validators");

        Ok(())
    }

    async fn register_operator(&mut self, operator: Operator) -> DbResult<()> {
        let rows_affected = sqlx::query(
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
        .execute(&mut *self.transaction)
        .await?
        .rows_affected();

        debug!(transaction_id = self.id, rows_affected, "register_operator");

        Ok(())
    }

    async fn commit(mut self, state: SyncStateUpdate) -> DbResult<()> {
        sqlx::query(
            "
                INSERT INTO sync_state (block_number, epoch, slot)
                VALUES ($1, $2, $3)
                ON CONFLICT (block_number)
                DO UPDATE SET epoch = $2, slot = $3
                ",
        )
        .bind(state.block_number as i64)
        .bind(state.epoch as i64)
        .bind(state.slot as i64)
        .execute(&mut *self.transaction)
        .await?;

        self.transaction.commit().await?;

        debug!(transaction_id = self.id, "commit");

        Ok(())
    }
}

#[async_trait::async_trait]
impl RegistryDb for SQLDb<Postgres> {
    type SyncTransaction = SQLSyncTransaction;

    async fn begin_sync(&self) -> DbResult<Self::SyncTransaction> {
        let transaction = self.conn.begin().await?;
        let id = self.next_id.fetch_add(1, std::sync::atomic::Ordering::Relaxed);

        Ok(SQLSyncTransaction { id, transaction })
    }

    async fn register_validators(&self, registrations: &[Registration]) -> DbResult<()> {
        let mut transaction = self.conn.begin().await?;

        for registration in registrations {
            sqlx::query(
                "
                INSERT INTO validator_registrations (pubkey, index, signature, expiry, operator, priority, source, last_update)
                VALUES ($1, $2, $3, $4, $5, $6, $7, NOW())
                "
            )
            .bind(registration.validator_pubkey.serialize())
            .bind(registration.validator_index as i64)
            .bind(registration.signature.as_ref().map(|s| s.serialize()))
            .bind(registration.expiry.to_string())
            .bind(registration.operator.to_vec())
            .bind(0) // TODO: priority
            .bind("none") // TODO: source
            .execute(&mut *transaction).await?;
        }

        transaction.commit().await?;

        Ok(())
    }

    // TODO: do we really want to delete the rows from the DB or just mark them as inactive?
    async fn deregister_validators(&self, deregistrations: &[Deregistration]) -> DbResult<()> {
        sqlx::query(
            "
            DELETE FROM validator_registrations
            WHERE pubkey = ANY($1)
            ",
        )
        .bind(deregistrations.iter().map(|d| d.validator_pubkey.serialize()).collect::<Vec<_>>())
        .execute(&self.conn)
        .await?;

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

    async fn list_registrations(&self) -> DbResult<Vec<Registration>> {
        let rows: Vec<ValidatorRegistrationRow> = sqlx::query_as(
            "
            SELECT pubkey, index, signature, expiry, gas_limit, operator, priority, source, last_update
            FROM validator_registrations
            ",
        )
        .fetch_all(&self.conn)
        .await?;

        rows.into_iter().map(TryInto::try_into).collect()
    }

    async fn get_registrations_by_pubkey(
        &self,
        pubkeys: &[BlsPublicKey],
    ) -> DbResult<Vec<Registration>> {
        let rows: Vec<ValidatorRegistrationRow> =
            sqlx::query_as(
                    "
                    SELECT pubkey, index, signature, expiry, gas_limit, operator, priority, source, last_update
                    FROM validator_registrations
                    WHERE pubkey = ANY($1)
                    ",
                )
                .bind(pubkeys.iter().map(|p| p.serialize()).collect::<Vec<_>>())
                .fetch_all(&self.conn)
                .await?;

        rows.into_iter().map(TryInto::try_into).collect()
    }

    async fn list_validators(&self) -> DbResult<Vec<RegistryEntry>> {
        let rows: Vec<ValidatorRegistrationRow> = sqlx::query_as(
            "
            SELECT vr.pubkey, vr.index, vr.signature, vr.expiry, vr.gas_limit, vr.operator, vr.priority, vr.source, vr.last_update, o.rpc
            FROM validator_registrations vr LEFT JOIN operators o ON o.signer = vr.operator
            ",
        )
        .fetch_all(&self.conn)
        .await?;

        rows.into_iter().map(TryInto::try_into).collect()
    }

    async fn get_validators_by_pubkey(
        &self,
        pubkeys: &[BlsPublicKey],
    ) -> DbResult<Vec<RegistryEntry>> {
        let rows: Vec<ValidatorRegistrationRow> =
            sqlx::query_as(
                "
                SELECT vr.pubkey, vr.index, vr.signature, vr.expiry, vr.gas_limit, vr.operator, vr.priority, vr.source, vr.last_update, o.rpc
                FROM validator_registrations vr LEFT JOIN operators o ON o.signer = vr.operator
                WHERE vr.pubkey = ANY($1)
                ",
            )
            .bind(pubkeys.iter().map(|p| p.serialize()).collect::<Vec<_>>())
            .fetch_all(&self.conn)
            .await?;

        rows.into_iter().map(TryInto::try_into).collect()
    }

    async fn get_validators_by_index(&self, indices: Vec<u64>) -> DbResult<Vec<RegistryEntry>> {
        let rows: Vec<ValidatorRegistrationRow> =
            sqlx::query_as(
                "
                SELECT vr.pubkey, vr.index, vr.signature, vr.expiry, vr.gas_limit, vr.operator, vr.priority, vr.source, vr.last_update, o.rpc
                FROM validator_registrations vr LEFT JOIN operators o ON o.signer = vr.operator
                WHERE vr.index = ANY($1)
                ",
            )
            .bind(indices.into_iter().map(|i| i as i64).collect::<Vec<_>>())
            .fetch_all(&self.conn)
            .await?;

        rows.into_iter().map(TryInto::try_into).collect()
    }

    async fn list_operators(&self) -> DbResult<Vec<Operator>> {
        let rows: Vec<OperatorRow> = sqlx::query_as(
            "
            SELECT signer, rpc, protocol, source, collateral_tokens, collateral_amounts, last_update
            FROM operators
            ",
        )
        .fetch_all(&self.conn)
        .await?;

        rows.into_iter().map(TryInto::try_into).collect()
    }

    async fn get_operators_by_signer(&self, signers: &[Address]) -> DbResult<Vec<Operator>> {
        let rows: Vec<OperatorRow> =
            sqlx::query_as(
                "
                SELECT signer, rpc, protocol, source, collateral_tokens, collateral_amounts, last_update
                FROM operators
                WHERE signer = ANY($1)
                ",
            )
            .bind(signers.iter().map(|s| s.to_vec()).collect::<Vec<_>>())
            .fetch_all(&self.conn)
            .await?;

        rows.into_iter().map(TryInto::try_into).collect()
    }

    async fn get_sync_state(&self) -> DbResult<SyncStateUpdate> {
        let (block_number, epoch, slot): (i64, i64, i64) = sqlx::query_as(
            "
            SELECT block_number, epoch, slot
            FROM sync_state
            ",
        )
        .fetch_one(&self.conn)
        .await?;

        Ok(SyncStateUpdate {
            block_number: block_number as u64,
            epoch: epoch as u64,
            slot: slot as u64,
        })
    }

    async fn update_sync_state(&self, state: SyncStateUpdate) -> DbResult<()> {
        sqlx::query(
            "
            INSERT INTO sync_state (block_number, epoch, slot)
            VALUES ($1, $2, $3)
            ON CONFLICT (block_number)
            DO UPDATE SET epoch = $2, slot = $3
            ",
        )
        .bind(state.block_number as i64)
        .bind(state.epoch as i64)
        .bind(state.slot as i64)
        .execute(&self.conn)
        .await?;

        Ok(())
    }
}
