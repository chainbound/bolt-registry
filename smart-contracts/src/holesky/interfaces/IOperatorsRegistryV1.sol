// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IBoltRestakingMiddlewareV1} from "./IBoltRestakingMiddlewareV1.sol";

/// @title IOperatorsRegistryV1
/// @notice An interface for the OperatorsRegistryV1 contract
interface IOperatorsRegistryV1 {
    /// @notice Emitted when a new operator is registered
    /// @param signer The address of the operator
    /// @param rpcEndpoint The rpc endpoint of the operator
    /// @param restakingMiddleware The address of the restaking middleware
    event OperatorRegistered(address signer, string rpcEndpoint, address restakingMiddleware);

    /// @notice Emitted when an operator is deregistered
    /// @param signer The address of the operator
    /// @param restakingMiddleware The address of the restaking middleware
    event OperatorDeregistered(address signer, address restakingMiddleware);

    /// @notice Emitted when an operator is paused
    /// @param signer The address of the operator
    /// @param restakingMiddleware The address of the restaking middleware
    event OperatorPaused(address signer, address restakingMiddleware);

    /// @notice Emitted when an operator is unpaused
    /// @param signer The address of the operator
    /// @param restakingMiddleware The address of the restaking middleware
    event OperatorUnpaused(address signer, address restakingMiddleware);

    /// @notice Returns the start timestamp of the registry contract
    function START_TIMESTAMP() external view returns (uint48);

    /// @notice Returns the duration of an epoch in seconds
    function EPOCH_DURATION() external view returns (uint48);

    /// @notice Returns the address of the EigenLayer restaking middleware
    function EIGENLAYER_RESTAKING_MIDDLEWARE() external view returns (IBoltRestakingMiddlewareV1);

    /// @notice Returns the address of the Symbiotic restaking middleware
    function SYMBIOTIC_RESTAKING_MIDDLEWARE() external view returns (IBoltRestakingMiddlewareV1);

    /// @notice Register an operator in the registry
    /// @param signer The address of the operator
    /// @param rpcEndpoint The rpc endpoint of the operator
    function registerOperator(address signer, string memory rpcEndpoint) external;

    /// @notice Deregister an operator from the registry
    /// @param signer The address of the operator
    function deregisterOperator(
        address signer
    ) external;

    /// @notice Pause an operator in the registry
    /// @param signer The address of the operator
    function pauseOperator(
        address signer
    ) external;

    /// @notice Unpause an operator in the registry, marking them as "active"
    /// @param signer The address of the operator
    function unpauseOperator(
        address signer
    ) external;

    /// @notice Returns the timestamp of when the current epoch started
    function getCurrentEpochStartTimestamp() external view returns (uint48);
}
