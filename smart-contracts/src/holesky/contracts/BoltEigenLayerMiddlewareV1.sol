// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

/// @title BoltEigenLayerMiddlewareV1
contract BoltEigenLayerMiddlewareV1 is OwnableUpgradeable, UUPSUpgradeable {

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     * This can be validated with the Openzeppelin Foundry Upgrades toolkit.
     *
     * Total storage slots: 50
     */
    uint256[45] private __gap;

    // ========= Initializer & Proxy functionality ========= //

    /// @notice Initialize the contract
    /// @param owner The address of the owner
    function initialize(
        address owner
    ) public initializer {
        __Ownable_init(owner);

        DELEGATION_MANAGER = DelegationManagerStorage(_eigenlayerDelegationManager);
        STRATEGY_MANAGER = StrategyManagerStorage(_eigenlayerStrategyManager);
        NAME_HASH = keccak256("EIGENLAYER");
    }

    /// @notice Upgrade the contract
    /// @param newImplementation The address of the new implementation
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    // ========= Middleware functions ========= //
}