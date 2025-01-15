// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title IOperatorsRegistryV1
/// @notice An interface for the OperatorsRegistryV1 contract
interface IOperatorsRegistryV1 {
    /// @notice The restaking protocols
    enum RestakingProtocol {
        EigenLayer,
        Symbiotic
    }

    /// @notice Operator struct
    struct Operator {
        address signer;
        string rpcEndpoint;
        address restakingMiddleware;
    }

    /// @notice A map of operators with their signer address as the key
    struct OperatorMap {
        EnumerableSet.AddressSet _keys;
        mapping(address key => Operator) _values;
    }

    /// @notice Emitted when a new operator is registered
    /// @param signer The address of the operator
    /// @param rpcEndpoint The rpc endpoint of the operator
    /// @param restakingMiddleware The address of the restaking middleware
    event OperatorRegistered(address signer, string rpcEndpoint, address restakingMiddleware);
}
