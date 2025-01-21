// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

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

    /// @notice Register an operator in the registry
    /// @param signer The address of the operator
    /// @param rpcEndpoint The rpc endpoint of the operator
    function registerOperator(address signer, string memory rpcEndpoint) external;

    /// @notice Deregister an operator from the registry
    /// @param signer The address of the operator
    function deregisterOperator(
        address signer
    ) external;

    /// @notice Update the rpc endpoint of an operator
    /// @param signer The address of the operator
    /// @param rpcEndpoint The new rpc endpoint
    /// @dev Only restaking middleware contracts can call this function
    function updateOperatorRpcEndpoint(address signer, string memory rpcEndpoint) external;
}
