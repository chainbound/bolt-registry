//! Contains the chain sync logic for the registry.
use std::{
    pin::Pin,
    task::{Context, Poll},
};

use tokio_stream::Stream;

use super::SyncStateUpdate;
use crate::primitives::beacon::PayloadAttribute;

/// An epoch transition event. Originates from the payload attribute stream, when the
/// (`proposal_slot` - 1) is a multiple of 32.
#[derive(Debug, Clone)]
pub(super) struct EpochTransition {
    pub(super) block_number: u64,
    pub(super) epoch: u64,
    pub(super) slot: u64,
}

// This transformation doesn't make much sense, but by having different types for the
// syncer and the database we keep the codebase consistent and allow for future DB changes.
impl From<EpochTransition> for SyncStateUpdate {
    fn from(transition: EpochTransition) -> Self {
        Self {
            block_number: transition.block_number,
            epoch: transition.epoch,
            slot: transition.slot,
        }
    }
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
                    let current_slot = pa.proposal_slot - 1;
                    // De-duplicate
                    if pa.proposal_slot <= this.proposal_slot {
                        continue;
                    }

                    // Update last known proposal slot
                    this.proposal_slot = pa.proposal_slot;

                    let epoch = current_slot / 32;
                    if epoch > this.epoch {
                        this.epoch = epoch;
                        return Poll::Ready(Some(EpochTransition {
                            epoch,
                            slot: current_slot,
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
    use tokio_stream::StreamExt;
    use tracing::{warn, Level};
    use url::Url;

    use crate::client::BeaconClient;

    #[tokio::test]
    async fn test_subscribe() {
        let _ = tracing_subscriber::fmt().with_max_level(Level::INFO).try_init();

        let Ok(beacon_url) = std::env::var("BEACON_URL") else {
            warn!("Skipping test because of missing BEACON_URL");
            return
        };

        let client = BeaconClient::new(Url::parse(&beacon_url).unwrap());
        let mut stream = client.subscribe_payload_attributes().await.unwrap();

        let mut head_stream = client.subscribe_new_heads().await.unwrap();

        let mut epoch_transition = false;

        loop {
            tokio::select! {
                Some(head) = head_stream.next() => {
                    println!("New Head: {:?} {:?}", head.slot, head.block);
                    if head.epoch_transition {
                        assert!(epoch_transition, "Epoch transition based on head stream");
                        break
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
