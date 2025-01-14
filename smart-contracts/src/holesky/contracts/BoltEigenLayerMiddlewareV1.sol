// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {IDelegationManager} from "@eigenlayer/src/contracts/interfaces/IDelegationManager.sol";
import {IllocationManager} from "@eigenlayer/src/contracts/interfaces/IAllocationManager.sol";
import {IStrategyManager} from "@eigenlayer/src/contracts/interfaces/IStrategyManager.sol";
import {IAVSRegistrar} from "@eigenlayer/src/contracts/interfaces/IAVSRegistrar.sol";
import {IStrategy} from "@eigenlayer/src/contracts/interfaces/IStrategy.sol";

/// @title BoltEigenLayerMiddlewareV1
contract BoltEigenLayerMiddlewareV1 is OwnableUpgradeable, UUPSUpgradeable, IAVSRegistrar {
    /// @notice Address of the EigenLayer Allocation Manager contract.
    IAllocationManager public ALLOCATION_MANAGER;

    /// @notice Address of the EigenLayer Delegation Manager contract.
    IDelegationManager public DELEGATION_MANAGER;

    /// @notice Address of the EigenLayer Strategy Manager contract.
    IStrategyManager public STRATEGY_MANAGER;

    /// @notice The name hash of the middleware
    bytes32 public NAME_HASH;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     * This can be validated with the Openzeppelin Foundry Upgrades toolkit.
     *
     * Total storage slots: 50
     */
    uint256[46] private __gap;

    // ========= Initializer & Proxy functionality ========= //

    /// @notice Initialize the contract
    /// @param owner The address of the owner
    /// @param _eigenlayerAllocationManager The address of the EigenLayer Allocation Manager contract
    /// @param _eigenlayerDelegationManager The address of the EigenLayer Delegation Manager contract
    /// @param _eigenlayerStrategyManager The address of the EigenLayer Strategy Manager contract
    function initialize(
        address owner,
        IAllocationManager _eigenlayerAllocationManager,
        IDelegationManager _eigenlayerDelegationManager,
        IStrategyManager _eigenlayerStrategyManager,
    ) public initializer {
        __Ownable_init(owner);

        ALLOCATION_MANAGER = _eigenlayerAllocationManager;
        DELEGATION_MANAGER = _eigenlayerDelegationManager;
        STRATEGY_MANAGER = _eigenlayerStrategyManager;
        NAME_HASH = keccak256("EIGENLAYER");
    }

    /// @notice Upgrade the contract
    /// @param newImplementation The address of the new implementation
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    // ========= AVS functions ========= //

    /// @notice Slash an operator in the AVS
    /// @param params The parameters for slashing the operator
    function slashOperator(SlashingParams calldata params) public {
        // TODO: Implement slashing logic

        // if the call proceeds to the AllocationManager, 
        // the operator will be slashed immediately and irreversibly.
        ALLOCATION_MANAGER.slashOperator(address(this), params);
    }

    // ========= AVS Registrar functions ========= //

    /// @notice Allows the AllocationManager to hook into the middleware to validate operator registration
    /// @param operator The address of the operator
    /// @param operatorSetIds The operator set IDs the operator is registering for
    /// @param data Arbitrary data the operator can provide as part of registration
    function registerOperator(address operator, uint32[] calldata operatorSetIds, bytes calldata data) external {
        // TODO: logic to decide if the operator can register to this AVS or not.
        // NOTE: this function is called by AllocationManager.registerForOperatorSets,
        // called by operators.

        // If this call reverts the registration will be unsuccessful.
    }

    /// @notice Allows the AllocationManager to hook into the middleware to validate operator deregistration
    /// @param operator The address of the operator
    /// @param operatorSetIds The operator set IDs the operator is deregistering from
    function deregisterOperator(address operator, uint32[] calldata operatorSetIds) external {
        // TODO: logic to decide if the operator can deregister from this AVS or not.
        // NOTE: this function is called by AllocationManager.deregisterFromOperatorSets,
        // called by operators.

        // Failure does nothing here: if this call reverts the deregistration will still go through.
        // this is done for security reasons, to prevent AVSs from being able to maliciously 
        // prevent operators from deregistering.
    }

    // ========= Admin functions ========= //

    /// @notice Create new operator sets for this AVS
    /// @param params The parameters for creating the operator sets
    function createOperatorSets(CreateSetParams[] calldata params) public onlyOwner {
        ALLOCATION_MANAGER.createOperatorSets(address(this), params);
    }

    /// @notice Add strategies to an operator set
    /// @param operatorSetId The ID of the operator set to add strategies to
    /// @param strategies The strategies to add
    function addStrategiesToOperatorSet(uint32 operatorSetId, IStrategy[] calldata strategies) public onlyOwner {
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
    function updateAVSMetadataURI(string calldata metadataURI) public onlyOwner {
        ALLOCATION_MANAGER.updateAVSMetadataURI(address(this), metadataURI);
    }
}
