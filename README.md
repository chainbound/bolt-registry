# Bolt Registry

This repository hosts the code for all the components of the bolt "hybrid registry".
In essence, it is a system that allows node operators to:

1. opt-in to bolt on-chain through a series of smart contracts
2. provide collateral through restaking protocols integration
3. manage their validator opt-in status through an off-chain API

For more details about bolt, please refer to the [Docs website][docs].

## Repository Structure

- [smart-contracts](./smart-contracts/): The smart contracts for operator registration and restaking integration.
- [registry-api](./registry-api/): The off-chain API service for managing validator opt-in status.
- [assets](./assets/): Static assets for storage of metadata.

<!-- links -->

[docs]: https://docs.boltprotocol.xyz
