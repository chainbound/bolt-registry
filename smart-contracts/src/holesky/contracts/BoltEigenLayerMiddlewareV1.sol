// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {
    IAllocationManager, IAllocationManagerTypes
} from "@eigenlayer/src/contracts/interfaces/IAllocationManager.sol";
import {IDelegationManager} from "@eigenlayer/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "@eigenlayer/src/contracts/interfaces/IStrategyManager.sol";
import {IAVSRegistrar} from "@eigenlayer/src/contracts/interfaces/IAVSRegistrar.sol";
import {IStrategy} from "@eigenlayer/src/contracts/interfaces/IStrategy.sol";

import {IBoltRestakingMiddlewareV1} from "../interfaces/IBoltRestakingMiddlewareV1.sol";
import {IOperatorsRegistryV1} from "../interfaces/IOperatorsRegistryV1.sol";

/**
 * @title BoltEigenLayerMiddlewareV1
 * @author Chainbound Developers <dev@chainbound.io>
 * @notice This contract is responsible for interacting with the EigenLayer restaking protocol contracts. It serves
 *         as AVS contract and implements the IAVSRegistrar interface as well.
 */
contract BoltEigenLayerMiddlewareV1 is
    OwnableUpgradeable,
    UUPSUpgradeable,
    IAVSRegistrar,
    IBoltRestakingMiddlewareV1
{
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Address of the EigenLayer Allocation Manager contract.
    IAllocationManager public ALLOCATION_MANAGER;

    /// @notice Address of the EigenLayer Delegation Manager contract.
    IDelegationManager public DELEGATION_MANAGER;

    /// @notice Address of the EigenLayer Strategy Manager contract.
    IStrategyManager public STRATEGY_MANAGER;

    /// @notice Address of the Bolt Operators Registry contract.
    IOperatorsRegistryV1 public OPERATORS_REGISTRY;

    /// @notice The name of the middleware
    bytes32 public NAME_HASH;

    /// @notice The list of whitelisted strategies for this AVS
    EnumerableSet.AddressSet internal whitelistedStrategies;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     * This can be validated with the Openzeppelin Foundry Upgrades toolkit.
     *
     * Total storage slots: 50
     */
    uint256[44] private __gap;

    // ========= Events ========= //

    /// @notice Emitted when a strategy is whitelisted
    event StrategyAddedToWhitelist(address strategy);

    /// @notice Emitted when a strategy is removed from the whitelist
    event StrategyRemovedFromWhitelist(address strategy);

    // ========= Initializer & Proxy functionality ========= //

    /// @notice Initialize the contract
    /// @param owner The address of the owner
    /// @param _eigenlayerAllocationManager The address of the EigenLayer Allocation Manager contract
    /// @param _eigenlayerDelegationManager The address of the EigenLayer Delegation Manager contract
    /// @param _eigenlayerStrategyManager The address of the EigenLayer Strategy Manager contract
    /// @param _operatorsRegistry The address of the Operators Registry contract
    function initialize(
        address owner,
        IAllocationManager _eigenlayerAllocationManager,
        IDelegationManager _eigenlayerDelegationManager,
        IStrategyManager _eigenlayerStrategyManager,
        IOperatorsRegistryV1 _operatorsRegistry
    ) public initializer {
        __Ownable_init(owner);

        ALLOCATION_MANAGER = _eigenlayerAllocationManager;
        DELEGATION_MANAGER = _eigenlayerDelegationManager;
        STRATEGY_MANAGER = _eigenlayerStrategyManager;
        OPERATORS_REGISTRY = _operatorsRegistry;
        NAME_HASH = keccak256("EIGENLAYER");
    }

    /// @notice Upgrade the contract
    /// @param newImplementation The address of the new implementation
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    // ========= AVS functions ========= //

    /// @notice Get the collaterals and amounts staked by an operator across the whitelisted strategies
    /// @param operator The operator address to get the collaterals and amounts staked for
    /// @return collaterals The collaterals staked by the operator
    /// @dev Assumes that the operator is registered and enabled
    function getOperatorCollaterals(
        address operator
    ) public view returns (address[] memory, uint256[] memory) {
        address[] memory collateralTokens = new address[](whitelistedStrategies.length());
        uint256[] memory amounts = new uint256[](whitelistedStrategies.length());

        // cast strategies to IStrategy; this should be zero-cost but Solidity doesn't allow it directly
        IStrategy[] memory strategies = new IStrategy[](whitelistedStrategies.length());
        for (uint256 i = 0; i < whitelistedStrategies.length(); i++) {
            strategies[i] = IStrategy(whitelistedStrategies.at(i));
        }

        // get the shares of the operator across all strategies
        uint256[] memory shares = DELEGATION_MANAGER.getOperatorShares(operator, strategies);

        // get the collateral tokens and amounts for the operator across all strategies
        for (uint256 i = 0; i < strategies.length; i++) {
            collateralTokens[i] = address(strategies[i].underlyingToken());
            amounts[i] = strategies[i].sharesToUnderlyingView(shares[i]);
        }

        return (collateralTokens, amounts);
    }

    /// @notice Get the CURRENT amount staked by an operator for a specific collateral
    /// @param operator The operator address to get the amount staked for
    /// @param collateral The collateral token address
    /// @return The amount staked by the operator for the collateral
    function getOperatorStake(address operator, address collateral) public view returns (uint256) {
        // TODO: impl

        return 0;
    }

    /// @notice Get the list of whitelisted strategies for this AVS
    /// @return The list of whitelisted strategies
    function getWhitelistedStrategies() public view returns (address[] memory) {
        return whitelistedStrategies.values();
    }

    // ========= AVS Registrar functions ========= //

    /// @notice Allows the AllocationManager to hook into the middleware to validate operator registration
    /// @param operator The address of the operator
    /// @param operatorSetIds The operator set IDs the operator is registering for
    /// @param data Arbitrary data the operator can provide as part of registration
    function registerOperator(address operator, uint32[] calldata operatorSetIds, bytes calldata data) external {
        // NOTE: this function is called by AllocationManager.registerForOperatorSets(),
        // called by operators when registering to this AVS. If this call reverts,
        // the registration will be unsuccessful.

        // We forward the call to the OperatorsRegistry to register the operator in its storage.
        OPERATORS_REGISTRY.registerOperator(operator, string(data));
    }

    /// @notice Allows the AllocationManager to hook into the middleware to validate operator deregistration
    /// @param operator The address of the operator
    /// @param operatorSetIds The operator set IDs the operator is deregistering from
    function deregisterOperator(address operator, uint32[] calldata operatorSetIds) external {
        // NOTE: this function is called by AllocationManager.deregisterFromOperatorSets,
        // called by operators when deregistering from this AVS.
        // Failure does nothing here: if this call reverts the deregistration will still go through.

        // We forward the call to the OperatorsRegistry to deregister the operator from its storage.
        OPERATORS_REGISTRY.deregisterOperator(operator);
    }

    // ========= Admin functions ========= //

    /// @notice Add a strategy to the whitelist
    /// @param strategy The strategy to add
    function addStrategyToWhitelist(
        address strategy
    ) public onlyOwner {
        require(strategy != address(0), "Invalid strategy address");
        require(!whitelistedStrategies.contains(strategy), "Strategy already whitelisted");
        require(STRATEGY_MANAGER.strategyIsWhitelistedForDeposit(IStrategy(strategy)), "Strategy not allowed");

        whitelistedStrategies.add(strategy);
        emit StrategyAddedToWhitelist(strategy);
    }

    /// @notice Remove a strategy from the whitelist
    /// @param strategy The strategy to remove
    function removeStrategyFromWhitelist(
        address strategy
    ) public onlyOwner {
        require(whitelistedStrategies.contains(strategy), "Strategy not whitelisted");

        whitelistedStrategies.remove(strategy);
        emit StrategyRemovedFromWhitelist(strategy);
    }

    /// @notice Create new operator sets for this AVS
    /// @param params The parameters for creating the operator sets
    function createOperatorSets(
        IAllocationManagerTypes.CreateSetParams[] calldata params
    ) public onlyOwner {
        for (uint256 i = 0; i < params.length; i++) {
            _checkAreAllStrategiesWhitelisted(params[i].strategies);
        }

        ALLOCATION_MANAGER.createOperatorSets(address(this), params);
    }

    /// @notice Add strategies to an operator set
    /// @param operatorSetId The ID of the operator set to add strategies to
    /// @param strategies The strategies to add
    function addStrategiesToOperatorSet(uint32 operatorSetId, IStrategy[] calldata strategies) public onlyOwner {
        _checkAreAllStrategiesWhitelisted(strategies);

        ALLOCATION_MANAGER.addStrategiesToOperatorSet(address(this), operatorSetId, strategies);
    }

    /// @notice Remove strategies from an operator set
    /// @param operatorSetId The ID of the operator set to remove strategies from
    /// @param strategies The strategies to remove
    function removeStrategiesFromOperatorSet(uint32 operatorSetId, IStrategy[] calldata strategies) public onlyOwner {
        ALLOCATION_MANAGER.removeStrategiesFromOperatorSet(address(this), operatorSetId, strategies);
    }

    /// @notice Update the metadata URI for this AVS
    /// @param metadataURI The new metadata URI
    function updateAVSMetadataURI(
        string calldata metadataURI
    ) public onlyOwner {
        ALLOCATION_MANAGER.updateAVSMetadataURI(address(this), metadataURI);
    }

    // ========== Internal helpers ========== //

    /// @notice Check if ALL the given strategies are whitelisted.
    /// If any of the strategies are not whitelisted, the function will revert.
    /// @param strategies The strategies to check
    function _checkAreAllStrategiesWhitelisted(
        IStrategy[] calldata strategies
    ) internal view {
        for (uint256 i = 0; i < strategies.length; i++) {
            require(whitelistedStrategies.contains(address(strategies[i])), "Strategy not whitelisted");
        }
    }
}
