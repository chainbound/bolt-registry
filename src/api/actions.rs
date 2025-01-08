use std::{
    pin::Pin,
    task::{Context, Poll},
};

use alloy::primitives::Address;
use tokio::sync::{mpsc, oneshot};
use tokio_stream::Stream;

use super::spec;
use crate::primitives::{
    registry::{Deregistration, Lookahead, Operator, Registration, RegistryEntry},
    BlsPublicKey,
};

/// An action to be executed by upstream services.
/// Actions are a mix of commands and queries.
pub(crate) enum Action {
    Register {
        registration: Registration,
        response: oneshot::Sender<Result<(), spec::RegistryError>>,
    },
    Deregister {
        deregistration: Deregistration,
        response: oneshot::Sender<Result<(), spec::RegistryError>>,
    },
    GetRegistrations {
        response: oneshot::Sender<Result<Vec<Registration>, spec::RegistryError>>,
    },
    GetValidators {
        response: oneshot::Sender<Result<Vec<RegistryEntry>, spec::RegistryError>>,
    },
    GetValidatorsByPubkeys {
        pubkeys: Vec<BlsPublicKey>,
        response: oneshot::Sender<Result<Vec<RegistryEntry>, spec::RegistryError>>,
    },
    GetValidatorsByIndices {
        indices: Vec<usize>,
        response: oneshot::Sender<Result<Vec<RegistryEntry>, spec::RegistryError>>,
    },
    GetValidatorByPubkey {
        pubkey: BlsPublicKey,
        response: oneshot::Sender<Result<RegistryEntry, spec::RegistryError>>,
    },
    GetOperators {
        response: oneshot::Sender<Result<Vec<Operator>, spec::RegistryError>>,
    },
    GetLookahead {
        epoch: u64,
        response: oneshot::Sender<Result<Lookahead, spec::RegistryError>>,
    },
    GetOperator {
        signer: Address,
        response: oneshot::Sender<Result<Operator, spec::RegistryError>>,
    },
}

/// A stream of API actions ([`Action`]).
/// These actions should be executed by upstream services.
/// Every action is a request to perform some operation on the registry, and
/// expects a response back.
pub(crate) struct ActionStream {
    rx: mpsc::Receiver<Action>,
}

impl ActionStream {
    /// Create a new action stream from a receiver.
    pub(super) const fn new(rx: mpsc::Receiver<Action>) -> Self {
        Self { rx }
    }
}

impl Stream for ActionStream {
    type Item = Action;

    fn poll_next(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        self.rx.poll_recv(cx)
    }
}
