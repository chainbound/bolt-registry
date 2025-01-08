//! Contains the chain sync logic for the registry.
use std::{
    pin::Pin,
    task::{Context, Poll},
};

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
    parent_block_number: u64,
}

impl EventsClient {
    pub(super) fn new(url: impl IntoUrl) -> Self {
        Self { client: Client::new(url.into_url().unwrap()) }
    }

    /// Subscribes to the payload attributes events. Returns a stream of filtered payload attributes
    /// in the form of [`PayloadAttribute`]. These events are emitted by beacon nodes in 3 cases:
    /// 1. Around the 12s mark.
    /// 2. When a new head is processed.
    /// 3. At a 4 seconds into a slot, without a new head.
    ///
    /// Note that multiple payload attribute events can be emitted for the same `proposal_slot`.
    pub(super) async fn subscribe_payload_attributes(
        &self,
    ) -> Result<impl Stream<Item = PayloadAttribute> + Send + Unpin, Error> {
        let events = self.client.get_events::<PayloadAttributesTopic>().await?;

        let stream = events.filter_map(|event| {
            event
                .map(|value| PayloadAttribute {
                    proposal_slot: value.data.proposal_slot,
                    parent_block_number: value.data.parent_block_number,
                })
                .ok()
        });

        Ok(stream)
    }
}

/// An epoch transition event. Originates from the payload attribute stream, when the
/// (`proposal_slot` - 1) is a multiple of 32.
#[derive(Debug, Clone)]
pub(super) struct EpochTransition {
    pub(super) epoch: u64,
    pub(super) slot: u64,
    pub(super) block_number: u64,
}

pub(super) struct EpochTransitionStream<S> {
    /// The current epoch. Used to emit the epoch transition event in case
    /// of a missed epoch transition.
    epoch: u64,
    /// The last known proposal slot, used for de-duplication.
    proposal_slot: u64,
    /// The payload attributes stream.
    pa_stream: S,
}

impl<S: Stream<Item = PayloadAttribute> + Unpin> EpochTransitionStream<S> {
    /// Creates a new [`EpochTransitionStream`] from a payload attribute stream.
    pub(super) const fn new(stream: S) -> Self {
        Self { epoch: 0, proposal_slot: 0, pa_stream: stream }
    }
}

impl<S> Stream for EpochTransitionStream<S>
where
    S: Stream<Item = PayloadAttribute> + Unpin,
{
    type Item = EpochTransition;

    fn poll_next(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        let this = self.get_mut();

        loop {
            match Pin::new(&mut this.pa_stream).poll_next(cx) {
                Poll::Ready(Some(pa)) => {
                    // De-duplicate
                    if pa.proposal_slot - 1 <= this.proposal_slot {
                        continue;
                    }

                    // Update last known proposal slot
                    this.proposal_slot = pa.proposal_slot;

                    let epoch = (pa.proposal_slot - 1) / 32;
                    if epoch > this.epoch {
                        this.epoch = epoch;
                        return Poll::Ready(Some(EpochTransition {
                            epoch,
                            slot: pa.proposal_slot - 1,
                            block_number: pa.parent_block_number,
                        }));
                    }
                }
                Poll::Ready(None) => return Poll::Ready(None),
                Poll::Pending => return Poll::Pending,
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use alloy::primitives::B256;
    use beacon_client::Topic;
    use serde::Deserialize;

    use super::*;

    struct NewHeadsTopic;

    impl Topic for NewHeadsTopic {
        const NAME: &'static str = "head";

        type Data = TestHead;
    }

    #[derive(Debug, Deserialize)]
    struct TestHead {
        slot: String,
        block: B256,
        epoch_transition: bool,
    }

    #[tokio::test]
    async fn test_subscribe() {
        let client = EventsClient::new("http://remotebeast:44400");
        let mut stream = client.subscribe_payload_attributes().await.unwrap();

        let mut head_stream = client.client.get_events::<NewHeadsTopic>().await.unwrap();

        let mut epoch_transition = false;

        loop {
            tokio::select! {
                Some(result) = head_stream.next() => {
                    match result {
                        Ok(head) => {
                            println!("New Head: {:?} {:?}", head.slot, head.block);
                            if head.epoch_transition {
                                assert!(epoch_transition, "Epoch transition based on head stream");
                                break
                            }
                        },
                        Err(e) => {
                            println!("Error: {:?}", e);
                        }
                    }
                },
                Some(payload) = stream.next() => {
                    println!("New PA:   {} {:?}", payload.proposal_slot, payload.parent_block_number);
                    if (payload.proposal_slot - 1) % 32 == 0 {
                        println!("Epoch transition: {:?}", payload.proposal_slot);
                        epoch_transition = true;
                    }
                }
            }
        }
    }
}
