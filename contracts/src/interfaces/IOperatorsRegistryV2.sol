// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IRestakingMiddlewareV1} from "./IRestakingMiddlewareV1.sol";

/// @title IOperatorsRegistryV2
/// @author Chainbound Developers <dev@chainbound.io>
/// @notice An interface for the OperatorsRegistryV2 contract
interface IOperatorsRegistryV2 {
    /// @notice Operator struct
    struct Operator {
        address signer;
        string rpcEndpoint;
        address restakingMiddleware;
        string extraData;
        // Field introduced in V2
        address[] authorizedSigners;
    }

    /// @notice Emitted when a new operator is registered
    /// @param operator The address of the operator
    /// @param rpcEndpoint The rpc endpoint of the operator
    /// @param restakingMiddleware The address of the restaking middleware
    /// @param extraData Arbitrary data the operator can provide as part of registration
    /// @param authorizedSigners The addresses authorized to sign commitment on behalf of the operator.
    event OperatorRegistered(
        address operator, string rpcEndpoint, address restakingMiddleware, string extraData, address[] authorizedSigners
    );

    /// @notice Emitted when an operator is deregistered
    /// @param operator The address of the operator
    /// @param restakingMiddleware The address of the restaking middleware
    event OperatorDeregistered(address operator, address restakingMiddleware);

    /// @notice Emitted when an operator is paused
    /// @param operator The address of the operator
    /// @param restakingMiddleware The address of the restaking middleware
    event OperatorPaused(address operator, address restakingMiddleware);

    /// @notice Emitted when an operator is unpaused
    /// @param operator The address of the operator
    /// @param restakingMiddleware The address of the restaking middleware
    event OperatorUnpaused(address operator, address restakingMiddleware);

    /// @notice Returns the start timestamp of the registry contract
    function START_TIMESTAMP() external view returns (uint48);

    /// @notice Returns the duration of an epoch in seconds
    function EPOCH_DURATION() external view returns (uint48);

    /// @notice Returns the address of the EigenLayer restaking middleware
    function EIGENLAYER_RESTAKING_MIDDLEWARE() external view returns (IRestakingMiddlewareV1);

    /// @notice Returns the address of the Symbiotic restaking middleware
    function SYMBIOTIC_RESTAKING_MIDDLEWARE() external view returns (IRestakingMiddlewareV1);

    /// @notice Register an operator in the registry
    /// @param operator The address of the operator
    /// @param rpcEndpoint The rpc endpoint of the operator
    /// @param extraData Arbitrary data the operator can provide as part of registration
    /// @param authorizedSigners The addresses authorized to sign commitment on behalf of the operator.
    function registerOperator(
        address operator,
        string memory rpcEndpoint,
        string memory extraData,
        address[] memory authorizedSigners
    ) external;

    /// @notice Deregister an operator from the registry
    /// @param operator The address of the operator
    function deregisterOperator(
        address operator
    ) external;

    /// @notice Update the rpc endpoint of an operator
    /// @param operator The address of the operator
    /// @param rpcEndpoint The new rpc endpoint
    /// @dev Only restaking middleware contracts can call this function
    function updateOperatorRpcEndpoint(address operator, string memory rpcEndpoint) external;

    /// @notice Pause an operator in the registry
    /// @param operator The address of the operator
    function pauseOperator(
        address operator
    ) external;

    /// @notice Unpause an operator in the registry, marking them as "active"
    /// @param operator The address of the operator
    function unpauseOperator(
        address operator
    ) external;

    /// @notice Returns all the operators saved in the registry, including inactive ones.
    /// @return operators The array of operators
    function getAllOperators() external view returns (Operator[] memory);

    /// @notice Returns the active operators in the registry.
    /// @return operators The array of active operators.
    function getActiveOperators() external view returns (Operator[] memory);

    /// @notice Get an operator struct and a bool indicating whether it is active
    /// @param operator The address of the operator
    /// @return op The operator struct
    /// @return isActive True if the operator is active, false otherwise.
    /// @return authorizedSigners The authorized signers of the operator
    function getOperator(
        address operator
    ) external view returns (Operator memory op, bool isActive, address[] memory authorizedSigners);

    /// @notice Returns true if the given address is an operator in the registry.
    /// @param operator The address of the operator.
    /// @return isOperator True if the address is an operator, false otherwise.
    function isOperator(
        address operator
    ) external view returns (bool);

    /// @notice Returns true if the given operator is registered AND active.
    /// @param operator The address of the operator
    /// @return isActiveOperator True if the operator is active, false otherwise.
    function isActiveOperator(
        address operator
    ) external view returns (bool);

    /// @notice Cleans up any expired operators (i.e. paused + IMMUTABLE_PERIOD has passed).
    function cleanup() external;

    /// @notice Returns the timestamp of when the current epoch started
    function getCurrentEpochStartTimestamp() external view returns (uint48);
}
