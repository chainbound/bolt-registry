// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

import {IOperatorsRegistryV1} from "../interfaces/IOperatorsRegistryV1.sol";
import {IBoltRestakingMiddlewareV1} from "../interfaces/IBoltRestakingMiddlewareV1.sol";
import {OperatorsLibV1} from "../lib/OperatorsLibV1.sol";

/// @title OperatorsRegistryV1
/// @notice A smart contract to store and manage Bolt operators
contract OperatorsRegistryV1 is OwnableUpgradeable, UUPSUpgradeable, IOperatorsRegistryV1 {
    using OperatorsLibV1 for OperatorsLibV1.OperatorMap;

    /// @notice The start timestamp of the contract, used as reference for time-based operations
    uint48 public START_TIMESTAMP;

    /// @notice The duration of an epoch in seconds, used for delaying opt-in/out operations
    uint48 public EPOCH_DURATION;

    /// @notice The set of bolt operators, indexed by their signer address
    OperatorsLibV1.OperatorMap private OPERATORS;

    /// @notice the address of the EigenLayer restaking middleware
    IBoltRestakingMiddlewareV1 public EIGENLAYER_RESTAKING_MIDDLEWARE;

    /// @notice The address of the Symbiotic restaking middleware
    IBoltRestakingMiddlewareV1 public SYMBIOTIC_RESTAKING_MIDDLEWARE;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     * This can be validated with the Openzeppelin Foundry Upgrades toolkit.
     *
     * Total storage slots: 50
     */
    uint256[43] private __gap;

    // ========= Errors ========= //

    /// @notice Error thrown when a non-middleware contract calls a middleware function
    error OnlyRestakingMiddlewares();

    /// @notice Error thrown when an invalid restaking protocol name is provided
    error InvalidRestakingProtocolName(string restakingProtocol);

    /// @notice Error thrown when an operator does not exist
    error OperatorDoesNotExist();

    /// @notice Error thrown when an invalid middleware address is provided
    error InvalidMiddlewareAddress();

    // ========= Initializer & Proxy functionality ========= //

    /// @notice Initialize the contract
    /// @param owner The address of the owner
    function initialize(address owner, uint48 epochDuration) public initializer {
        __Ownable_init(owner);

        START_TIMESTAMP = uint48(block.timestamp);
        EPOCH_DURATION = epochDuration;
    }

    /// @notice Upgrade the contract
    /// @param newImplementation The address of the new implementation
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    // ========= Modifiers ========= //

    /// @notice Only one of the middleware contracts can call the function
    modifier onlyMiddleware() {
        require(
            msg.sender == address(EIGENLAYER_RESTAKING_MIDDLEWARE)
                || msg.sender == address(SYMBIOTIC_RESTAKING_MIDDLEWARE),
            OnlyRestakingMiddlewares()
        );
        _;
    }

    // ========= Public helpers ========= //

    /// @notice Returns the timestamp of when the current epoch started
    function getCurrentEpochStartTimestamp() public view returns (uint48) {
        uint48 currentEpoch = (Time.timestamp() - START_TIMESTAMP) / EPOCH_DURATION;
        return START_TIMESTAMP + currentEpoch * EPOCH_DURATION;
    }

    // ========= Operators functions ========= //
    //
    // The operator lifecycle looks as follows:
    // 1. Register, and become active immediately. The operator can then manage their
    //    restaking positions through the restaking protocol.
    // 2. Pause, and become inactive. After a delay, the operator won't be slashable anymore,
    //    but they can still manage and rebalance their positions.
    // 3. Unpause, and become active again. After a delay, the operator can be slashed again.
    // 4. Deregister, and become inactive. After a delay, the operator won't be part of the AVS anymore.

    /// @notice Register an operator in the registry
    /// @param signer The address of the operator
    /// @param rpcEndpoint The rpc endpoint of the operator
    /// @dev Only restaking middleware contracts can call this function
    function registerOperator(address signer, string memory rpcEndpoint) external onlyMiddleware {
        OPERATORS.add(signer, rpcEndpoint, msg.sender);
        emit OperatorRegistered(signer, rpcEndpoint, msg.sender);
    }

    /// @notice Pause an operator in the registry
    /// @param signer The address of the operator
    /// @dev Only restaking middleware contracts can call this function.
    /// @dev Paused operators are considered "inactive" until they are unpaused.
    function pauseOperator(
        address signer
    ) external onlyMiddleware {
        OPERATORS.pause(signer);
        emit OperatorPaused(signer, msg.sender);
    }

    /// @notice Unpause an operator in the registry, marking them as "active"
    /// @param signer The address of the operator
    /// @dev Only restaking middleware contracts can call this function
    /// @dev Operators need to be paused and wait for IMMUTABLE_PERIOD() before they can be deregistered.
    function unpauseOperator(
        address signer
    ) external onlyMiddleware {
        OPERATORS.unpause(signer);
        emit OperatorUnpaused(signer, msg.sender);
    }

    /// @notice Update the rpc endpoint of an operator
    /// @param signer The address of the operator
    /// @param newRpcEndpoint The new rpc endpoint
    /// @dev Only restaking middleware contracts can call this function
    function updateOperatorRpcEndpoint(address signer, string memory newRpcEndpoint) external onlyMiddleware {
        OPERATORS.updateRpcEndpoint(signer, newRpcEndpoint);
    }

    /// @notice Deregister an operator from the registry
    /// @param signer The address of the operator
    /// @dev Only restaking middleware contracts can call this function
    /// @dev Operators need to be paused and wait for IMMUTABLE_PERIOD() before they can be deregistered.
    function deregisterOperator(
        address signer
    ) external onlyMiddleware {
        require(OPERATORS.contains(signer), OperatorDoesNotExist());

        OPERATORS.remove(signer);
        emit OperatorDeregistered(signer, msg.sender);
    }

    /// @notice Returns all the operators saved in the registry
    /// @return operators The array of operators
    function getAllOperators() public view returns (OperatorsLibV1.Operator[] memory operators) {
        return OPERATORS.getAll();
    }

    /// @notice Returns the operator with the given signer address, and whether the operator is active
    /// @param signer The address of the operator
    /// @return operator The operator struct and a boolean indicating if the operator is active
    /// @dev Reverts if the operator does not exist
    function getOperator(
        address signer
    ) public view returns (OperatorsLibV1.Operator memory operator, bool isActive) {
        return OPERATORS.get(signer);
    }

    /// @notice Returns true if the given address is an operator in the registry
    /// @param signer The address of the operator
    /// @return isOperator True if the address is an operator, false otherwise
    function isOperator(
        address signer
    ) public view returns (bool) {
        return OPERATORS.contains(signer);
    }

    // ========= Restaking Middlewres ========= //

    /// @notice Update the address of a restaking middleware contract address
    /// @param restakingProtocol The name of the restaking protocol
    /// @param newMiddleware The address of the new restaking middleware
    function updateRestakingMiddleware(
        string calldata restakingProtocol,
        IBoltRestakingMiddlewareV1 newMiddleware
    ) public onlyOwner {
        require(address(newMiddleware) != address(0), InvalidMiddlewareAddress());

        bytes32 protocolNameHash = keccak256(abi.encodePacked(restakingProtocol));

        if (protocolNameHash == keccak256("EIGENLAYER")) {
            EIGENLAYER_RESTAKING_MIDDLEWARE = newMiddleware;
        } else if (protocolNameHash == keccak256("SYMBIOTIC")) {
            SYMBIOTIC_RESTAKING_MIDDLEWARE = newMiddleware;
        } else {
            revert InvalidRestakingProtocolName(restakingProtocol);
        }
    }
}
