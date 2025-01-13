// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {Operators} from "@symbiotic/middleware-sdk/extensions/operators/Operators.sol";
import {SharedVaults} from "@symbiotic/middleware-sdk/extensions/SharedVaults.sol";
import {KeyManagerAddress} from "@symbiotic/middleware-sdk/extensions/managers/keys/KeyManagerAddress.sol";
import {EqualStakePower} from "@symbiotic/middleware-sdk/extensions/managers/stake-powers/EqualStakePower.sol";
import {EpochCapture} from "@symbiotic/middleware-sdk/extensions/managers/capture-timestamps/EpochCapture.sol";
import {ECDSASig} from "@symbiotic/middleware-sdk/extensions/managers/sigs/ECDSASig.sol";
import {OwnableAccessManager} from "@symbiotic/middleware-sdk/extensions/managers/access/OwnableAccessManager.sol";

import {Subnetwork} from "@symbiotic/core/contracts/libraries/Subnetwork.sol";
import {INetworkRegistry} from "@symbiotic/core/interfaces/INetworkRegistry.sol";

/**
 * @title SymbioticMiddlewareV1
 * @author Chainbound Developers <dev@chainbound.io>
 * @notice This contract is responsible for interacting with the Symbiotic restaking protocol contracts.
 * @dev This contract inherits from Operators, SharedVaults, KeyManagerAddress, OwnableUpgradeable, and UUPSUpgradeable.
 *      - Operators: Provides operator management (keys, vaults, registration)
 *      - KeyManagerAddress: Manages storage and validation of operator keys using address values
 *      - ECDSASig: Verify ECDSA keys against operator addresses
 *      - EqualStakePower: Equal stake to power for all registered vaults
 */
contract SymbioticMiddlewareV1 is
    Operators,
    KeyManagerAddress,
    ECDSASig,
    EqualStakePower,
    EpochCapture,
    OwnableAccessManager,
    UUPSUpgradeable
{
    using Subnetwork for address;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     * This can be validated with the Openzeppelin Foundry Upgrades toolkit.
     *
     * Total storage slots: 50
     */
    uint256[50] private __gap;

    modifier onlyOwner() {
        _checkAccess();
        _;
    }

    /**
     * @notice Constructor for initializing the SymbioticMiddlewareV1 contract
     * @param owner The address of the owner
     * @param network The address of the network
     * @param networkRegistry The address of the network registry
     * @param slashingWindow The duration of the slashing window (unused in V1)
     * @param vaultRegistry The address of the vault registry
     * @param operatorRegistry The address of the operator registry
     * @param operatorNetOptin The address of the operator network opt-in service
     * @param reader The address of the reader contract used for delegatecall
     */
    function initialize(
        address owner,
        address network,
        address networkRegistry,
        uint48 slashingWindow,
        address vaultRegistry,
        address operatorRegistry,
        address operatorNetOptin,
        address reader
    ) public initializer {
        // Register the network
        INetworkRegistry(networkRegistry).registerNetwork();

        // Initialize middleware
        __BaseMiddleware_init(network, slashingWindow, vaultRegistry, operatorRegistry, operatorNetOptin, reader);

        // Initialize owner access
        __OwnableAccessManager_init(owner);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
