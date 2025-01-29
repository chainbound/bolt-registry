# List all available commands
default:
    @just --list --unsorted

# Run the development server locally
dev loglevel='debug':
    @echo "Starting bolt-registry in development mode with loglevel: {{loglevel}}"
    cd registry && RUST_LOG=bolt_registry={{loglevel}} cargo watch -x run

# Generate new contract bindings for the registry
abigen:
    @echo "Generating new contract bindings"
    @just _generate_and_export_abi SymbioticMiddlewareV1 ../registry/src/chainio/artifacts
    @just _generate_and_export_abi OperatorsRegistryV1 ../registry/src/chainio/artifacts
    @just _generate_and_export_abi EigenLayerMiddlewareV3 ../registry/src/chainio/artifacts

# Helper to generate and export the ABI of a contract to a file
_generate_and_export_abi contract_name out_dir:
    cd contracts && forge inspect {{contract_name}} abi > {{out_dir}}/{{contract_name}}.json
