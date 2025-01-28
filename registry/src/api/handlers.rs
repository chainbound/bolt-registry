use std::sync::Arc;

use alloy::primitives::Address;
use axum::{extract::{Path, Query, State}, response::IntoResponse, Json};
use utoipa::OpenApi;

use crate::primitives::{
    registry::{
        Deregistration, DeregistrationBatch, Lookahead, Operator,
        Registration, RegistrationBatch, RegistryEntry
    },
    BlsPublicKey,
};

use super::{
    DiscoverySpec,
    RegistryApi,
    ValidatorFilter,
    ValidatorSpec,
    DISCOVERY_LOOKAHEAD_PATH,
    DISCOVERY_OPERATORS_PATH,
    DISCOVERY_OPERATOR_PATH,
    DISCOVERY_VALIDATORS_PATH,
    DISCOVERY_VALIDATOR_PATH,
    VALIDATORS_DEREGISTER_PATH,
    VALIDATORS_REGISTER_PATH,
    VALIDATORS_REGISTRATIONS_PATH,
};

#[derive(OpenApi, Debug)]
#[openapi(
    info(
        title = "Bolt Registry API",
        description = "This API provides access to Bolt protocol validators and operators information."
    ),
    components(schemas(
        Registration,
        Deregistration,
        RegistryEntry,
        Operator,
        Lookahead,
        RegistrationBatch,
        DeregistrationBatch,
    )),
    paths(
        register,
        deregister,
        get_registrations,
        get_validators,
        get_validator_by_pubkey,
        get_operators,
        get_operator_by_signer,
        get_lookahead,
    )
)]
pub(crate) struct ApiDoc;

/// Registers a new validator.
#[utoipa::path(post, path = VALIDATORS_REGISTER_PATH, request_body = RegistrationBatch, responses(
    (status = 200, description = "Success")
))]
pub(crate) async fn register(
    State(api): State<Arc<RegistryApi>>,
    Json(registration): Json<RegistrationBatch>,
) -> impl IntoResponse {
    api.register(registration).await
}

/// Deregisters a validator.
#[utoipa::path(post, path = VALIDATORS_DEREGISTER_PATH, request_body = DeregistrationBatch, responses(
    (status = 200, description = "Success")
))]
pub(crate) async fn deregister(
    State(api): State<Arc<RegistryApi>>,
    Json(deregistration): Json<DeregistrationBatch>,
) -> impl IntoResponse {
    api.deregister(deregistration).await
}

/// Gets all validator registrations.
#[utoipa::path(get, path = VALIDATORS_REGISTRATIONS_PATH, responses(
    (status = 200, description = "Success", body = Vec<Registration>)
))]
pub(crate) async fn get_registrations(State(api): State<Arc<RegistryApi>>) -> impl IntoResponse {
    api.get_registrations().await.map(Json)
}

/// Gets all validators.
#[utoipa::path(get, path = DISCOVERY_VALIDATORS_PATH,
    params(
        ("pubkeys" = Option<Vec<BlsPublicKey>>, Query, description = "The public keys of the validators to get."),
        ("indices" = Option<Vec<u64>>, Query, description = "The indices of the validators to get."),
    ),
    responses(
        (status = 200, description = "Success", body = Vec<RegistryEntry>),
    )
)]
pub(crate) async fn get_validators(
    State(api): State<Arc<RegistryApi>>,
    Query(filter): Query<ValidatorFilter>,
) -> impl IntoResponse {
    match (filter.pubkeys, filter.indices) {
        (Some(pubkeys), None) => api.get_validators_by_pubkeys(pubkeys).await.map(Json),
        (None, Some(indices)) => api.get_validators_by_indices(indices).await.map(Json),
        _ => api.get_validators().await.map(Json),
    }
}

/// Gets a validator by its public key.
#[utoipa::path(
    get, 
    path = DISCOVERY_VALIDATOR_PATH, 
    params(("pubkey" = BlsPublicKey, description = "The public key of the validator to get.")), 
    responses(
        (status = 200, description = "Success", body = RegistryEntry),
        (status = 404, description = "Not Found", body = String, example = "Not found"),
    )
)]
pub(crate) async fn get_validator_by_pubkey(
    State(api): State<Arc<RegistryApi>>,
    Path(pubkey): Path<BlsPublicKey>,
) -> impl IntoResponse {
    api.get_validator_by_pubkey(pubkey).await.map(Json)
}

/// Gets all operators.
#[utoipa::path(get, path = DISCOVERY_OPERATORS_PATH, responses(
    (status = 200, description = "Success", body = Vec<Operator>)
))]
pub(crate) async fn get_operators(State(api): State<Arc<RegistryApi>>) -> impl IntoResponse {
    api.get_operators().await.map(Json)
}

/// Gets an operator by its signer.
#[utoipa::path(
    get, 
    path = DISCOVERY_OPERATOR_PATH, 
    params(("signer" = String, description = "The address of the operator to get")), 
    responses(
        (status = 200, description = "Success", body = Operator),
        (status = 404, description = "Not Found", body = String, example = "Not found"),
    )
)]
pub(crate) async fn get_operator_by_signer(
    State(api): State<Arc<RegistryApi>>,
    Path(signer): Path<Address>,
) -> impl IntoResponse {
    api.get_operator_by_signer(signer).await.map(Json)
}

/// Gets the lookahead for an epoch.
#[utoipa::path(
    get, 
    path = DISCOVERY_LOOKAHEAD_PATH, 
    params(("epoch" = u64, description = "The epoch to get the lookahead for.")),
    responses(
        (status = 200, description = "Success", body = Lookahead),
    )
)]
pub(crate) async fn get_lookahead(
    State(api): State<Arc<RegistryApi>>,
    Path(epoch): Path<u64>,
) -> impl IntoResponse {
    api.get_lookahead(epoch).await.map(Json)
}