# Bolt Registry

This repository hosts the code for all the components of the bolt "hybrid registry".
In essence, it is a system that allows node operators to:

1. opt-in to bolt on-chain through a series of smart contracts
2. provide collateral through restaking protocols integration
3. manage their validator opt-in status through an off-chain API

For more details about bolt, please refer to the [Docs website][docs].

## Repository Structure

- [contracts](./contracts/): The smart contracts for operator registration and restaking integration.
- [registry](./registry/): The off-chain service for managing validator opt-in status and serving the API.
- [assets](./assets/): Static assets for storage of metadata.

<!-- links -->

[docs]: https://docs.boltprotocol.xyz
