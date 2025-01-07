//! Database row types

use alloy::primitives::{Address, U256};

use crate::primitives::{BlsPublicKey, BlsSignature};

use super::{DbError, Operator, Registration};

#[derive(sqlx::FromRow, Debug)]
pub(crate) struct OperatorRow {
    pub signer: Vec<u8>,                    // BYTEA
    pub rpc: String,                        // TEXT
    pub protocol: Option<String>,           // PROTOCOL_ENUM (OPTIONAL)
    pub source: String,                     // SOURCE_ENUM
    pub collateral_tokens: Vec<Vec<u8>>,    // BYTEA[]
    pub collateral_amounts: Vec<Vec<u8>>,   // BYTEA[]
    pub last_update: chrono::NaiveDateTime, // TIMESTAMP
}

impl TryFrom<OperatorRow> for Operator {
    type Error = DbError;

    fn try_from(value: OperatorRow) -> Result<Self, Self::Error> {
        let collateral_tokens = value
            .collateral_tokens
            .into_iter()
            .map(|a| parse_address(&a))
            .collect::<Result<_, _>>()?;

        let collateral_amounts = value
            .collateral_amounts
            .into_iter()
            .map(|a| parse_u256(&a))
            .collect::<Result<_, _>>()?;

        Ok(Self {
            signer: parse_address(&value.signer)?,
            rpc_endpoint: value.rpc.parse()?,
            collateral_tokens,
            collateral_amounts,
        })
    }
}

#[derive(sqlx::FromRow, Debug)]
pub(crate) struct ValidatorRegistrationRow {
    pub pubkey: Vec<u8>,                    // BYTEA
    pub signature: Vec<u8>,                 // BYTEA
    pub expiry: i64,                        // BIGINT
    pub gas_limit: i64,                     // BIGINT
    pub operator: Vec<u8>,                  // BYTEA
    pub priority: i32,                      // SMALLINT
    pub source: String,                     // SOURCE_ENUM
    pub last_update: chrono::NaiveDateTime, // TIMESTAMP
}

impl TryFrom<ValidatorRegistrationRow> for Registration {
    type Error = DbError;

    fn try_from(value: ValidatorRegistrationRow) -> Result<Self, Self::Error> {
        Ok(Self {
            validator_pubkeys: vec![parse_pubkey(&value.pubkey)?],
            signatures: vec![parse_signature(&value.signature)?],
            operator: parse_address(&value.operator)?,
            gas_limit: value.gas_limit as u64,
            expiry: value.expiry as u64,
        })
    }
}

/// Utility function to parse an address from a byte array.
fn parse_address(value: &[u8]) -> Result<Address, DbError> {
    Ok(Address::try_from(value)?)
}

/// Utility function to parse a U256 from a LE byte array.
fn parse_u256(value: &[u8]) -> Result<U256, DbError> {
    U256::try_from_le_slice(value).ok_or(DbError::ParseUint("invalid U256"))
}

/// Utility function to parse a BLS public key from a byte array.
fn parse_pubkey(value: &[u8]) -> Result<BlsPublicKey, DbError> {
    Ok(BlsPublicKey::from(
        bls::PublicKey::deserialize_uncompressed(value).map_err(DbError::ParseBLSKey)?,
    ))
}

/// Utility function to parse a BLS signature from a byte array.
fn parse_signature(value: &[u8]) -> Result<BlsSignature, DbError> {
    bls::Signature::deserialize(value).map_err(DbError::ParseBLSKey)
}
