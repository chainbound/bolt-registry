use alloy::primitives::B256;
use beacon_api_client::Topic;
use serde::Deserialize;

/// A payload attribute event.
#[derive(Debug, Clone)]
pub(crate) struct PayloadAttribute {
    pub(crate) proposal_slot: u64,
    pub(crate) parent_block_number: u64,
}

pub(crate) struct NewHeadsTopic;

impl Topic for NewHeadsTopic {
    const NAME: &'static str = "head";

    type Data = NewHead;
}

#[derive(Debug, Deserialize)]
pub(crate) struct NewHead {
    #[serde(with = "as_str")]
    pub(crate) slot: u64,
    pub(crate) block: B256,
    pub(crate) epoch_transition: bool,
}

pub mod as_str {
    use serde::Deserialize;
    use std::{fmt::Display, str::FromStr};

    pub fn serialize<S, T: Display>(data: T, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        serializer.collect_str(&data.to_string())
    }

    pub fn deserialize<'de, D, T, E>(deserializer: D) -> Result<T, D::Error>
    where
        D: serde::Deserializer<'de>,
        T: FromStr<Err = E>,
        E: Display,
    {
        let s = String::deserialize(deserializer)?;
        T::from_str(&s).map_err(serde::de::Error::custom)
    }
}
