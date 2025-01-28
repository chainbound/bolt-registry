pub(crate) mod abi {
    use alloy::sol;

    sol!(
        #[sol(rpc)]
        SymbioticMiddleware,
        "src/chainio/artifacts/SymbioticMiddlewareV1.json"
    );
    sol!(
        #[sol(rpc)]
        OperatorsRegistry,
        "src/chainio/artifacts/OperatorsRegistryV1.json"
    );
    sol!(
        #[sol(rpc)]
        EigenLayerMiddleware,
        "src/chainio/artifacts/EigenLayerMiddlewareV2.json"
    );
}
