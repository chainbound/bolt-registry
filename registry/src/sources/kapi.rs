use alloy::primitives::Address;
use reqwest::{IntoUrl, RequestBuilder};
use serde::{Deserialize, Serialize};
use url::Url;

use crate::primitives::{registry::RegistryEntry, BlsPublicKey};

use super::{ExternalSource, SourceError};

const VALIDATORS_PATH: &str = "/v1/preconfs/lido-bolt/validators";

const DEFAULT_GAS_LIMIT: u64 = 10_000_000;

/// Lido Keys API external source.
pub(crate) struct KeysApi {
    client: reqwest::Client,
    /// The base URL of the API.
    url: Url,
}

#[derive(Debug, Serialize)]
struct RequestBody<'a> {
    #[serde(rename = "pubKeys")]
    pubkeys: &'a [BlsPublicKey],
}

#[derive(Debug, Deserialize)]
struct ResponseBody {
    data: Vec<ValidatorEntry>,
}

#[derive(Debug, Deserialize)]
struct ErrorResponse {
    #[serde(rename = "statusCode")]
    status_code: u16,
    message: String,
    error: String,
}

#[derive(Debug, Deserialize)]
struct ValidatorEntry {
    #[serde(rename = "pubKey")]
    pubkey: BlsPublicKey,
    #[serde(rename = "proxyKey")]
    proxy_key: Address,
    #[serde(rename = "rpcUrl")]
    rpc_url: Url,
}

impl KeysApi {
    pub(crate) fn new(base_url: impl IntoUrl) -> Self {
        Self {
            client: reqwest::Client::new(),
            url: base_url.into_url().expect("failed to parse URL"),
        }
    }

    #[inline]
    fn get_validators_request(&self, pubkeys: &[BlsPublicKey]) -> RequestBuilder {
        let url = self.url.join(VALIDATORS_PATH).unwrap();

        let body = RequestBody { pubkeys };

        self.client.post(url).json(&body)
    }
}

#[async_trait::async_trait]
impl ExternalSource for KeysApi {
    fn name(&self) -> &'static str {
        "lido-keys-api"
    }

    /// Fetches validators by `pubkeys` from the API.
    async fn get_validators(
        &self,
        pubkeys: &[BlsPublicKey],
    ) -> Result<Vec<RegistryEntry>, SourceError> {
        let res = self.get_validators_request(pubkeys).send().await?;
        if !res.status().is_success() {
            let response = res.json::<ErrorResponse>().await?;

            return Err(SourceError::Other(format!(
                "API error: {} ({})",
                response.message, response.error
            )));
        }

        let response: ResponseBody = res.json().await?;

        response
            .data
            .into_iter()
            .map(|entry| {
                Ok(RegistryEntry {
                    validator_pubkey: entry.pubkey,
                    operator: entry.proxy_key,
                    gas_limit: DEFAULT_GAS_LIMIT,
                    rpc_endpoint: entry.rpc_url,
                })
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_keys_api() -> eyre::Result<()> {
        // Url displays a trailing backslash, so need to add that here
        let url = "http://34.88.187.80:30303/";
        let keys_api = KeysApi::new(url);

        assert_eq!(keys_api.url.as_str(), url);
        Ok(())
    }

    #[tokio::test]
    async fn test_get_validators_request() -> eyre::Result<()> {
        let url = "http://34.88.187.80:30303/";
        let keys_api = KeysApi::new(url);

        let pubkeys = vec![BlsPublicKey::random(), BlsPublicKey::random(), BlsPublicKey::random()];

        let request = keys_api.get_validators_request(&pubkeys);

        println!("{}", request.build()?.url());

        let response = keys_api.get_validators(&pubkeys).await?;

        println!("{response:?}");

        Ok(())
    }
}
