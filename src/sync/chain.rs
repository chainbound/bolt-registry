//! Contains the chain sync logic for the registry.
use beacon_client::{mainnet::MainnetClientTypes, Client, Error, PayloadAttributesTopic};
use reqwest::IntoUrl;
use tokio_stream::{Stream, StreamExt};

/// A client that can subscribe to SSE events.
pub(super) struct EventsClient {
    client: Client<MainnetClientTypes>,
}

/// A payload attribute event.
#[derive(Debug, Clone)]
pub(super) struct PayloadAttribute {
    proposal_slot: u64,
    proposal_epoch: u64,
    parent_block_number: u64,
}

impl EventsClient {
    pub(crate) fn new(url: impl IntoUrl) -> Self {
        Self { client: Client::new(url.into_url().unwrap()) }
    }

    /// Subscribes to the payload attributes events. Returns a stream of filtered payload attributes
    /// in the form of [`PayloadAttribute`].
    pub(crate) async fn subscribe_payload_attributes(
        &self,
    ) -> Result<impl Stream<Item = PayloadAttribute>, Error> {
        let events = self.client.get_events::<PayloadAttributesTopic>().await?;

        let stream = events.filter_map(|event| {
            event
                .map(|value| PayloadAttribute {
                    proposal_slot: value.data.proposal_slot,
                    proposal_epoch: value.data.proposal_slot / 32,
                    parent_block_number: value.data.parent_block_number,
                })
                .ok()
        });

        Ok(stream)
    }
}

struct ChainSyncer {
    client: EventsClient,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_subscribe() {
        let client = EventsClient::new("http://remotebeast:44400");
        let stream = client.subscribe_payload_attributes().await.unwrap();

        let mut stream = stream.take(1);
        let payload = stream.next().await.unwrap();

        println!("{payload:?}");
    }
}
