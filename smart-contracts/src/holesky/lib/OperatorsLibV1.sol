// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {PauseableEnumerableSet} from "@symbiotic/middleware-sdk/libraries/PauseableEnumerableSet.sol";

/// @title Operators Library
/// @notice A library for managing operators in storage.
library OperatorsLibV1 {
    using PauseableEnumerableSet for PauseableEnumerableSet.AddressSet;

    /// @notice The time period for an operator to be disabled before they can be unregistered.
    uint48 public constant IMMUTABLE_PERIOD = uint48(1 days);

    /// @notice Operator struct
    struct Operator {
        address signer;
        string rpcEndpoint;
        address restakingMiddleware;
        string extraData;
    }

    /// @notice A map of operators with their signer address as the key
    struct OperatorMap {
        PauseableEnumerableSet.AddressSet _keys;
        mapping(address key => Operator) _values;
    }

    /// @notice Pause an operator in the map
    /// @param self The OperatorMap
    /// @param signer The address of the operator
    /// @dev This is used to pause an operator, considering them "inactive" until they are unpaused.
    function pause(OperatorMap storage self, address signer) internal {
        self._keys.pause(Time.timestamp(), signer);
    }

    /// @notice Unpause an operator in the map
    /// @param self The OperatorMap
    /// @param signer The address of the operator
    /// @dev This is used to unpause an operator that was paused at least IMMUTABLE_PERIOD ago.
    function unpause(OperatorMap storage self, address signer) internal {
        self._keys.unpause(Time.timestamp(), IMMUTABLE_PERIOD, signer);
    }

    /// @notice Add an operator to the map, considering it active.
    /// @param self The OperatorMap
    /// @param signer The address of the operator
    /// @param rpcEndpoint The rpc endpoint of the operator
    /// @param restakingMiddleware The address of the restaking middleware
    function add(
        OperatorMap storage self,
        address signer,
        string memory rpcEndpoint,
        address restakingMiddleware,
        string memory extraData
    ) internal {
        require(signer != address(0), "Invalid operator address");
        require(bytes(rpcEndpoint).length > 0, "Invalid rpc endpoint");

        self._keys.register(Time.timestamp(), signer);
        self._values[signer] = Operator(signer, rpcEndpoint, restakingMiddleware, extraData);
    }

    /// @notice Remove an operator from the map
    /// @param self The OperatorMap
    /// @param signer The address of the operator
    /// @dev Operators need to be paused and wait for IMMUTABLE_PERIOD before they can be removed.
    function remove(OperatorMap storage self, address signer) internal {
        self._keys.unregister(Time.timestamp(), IMMUTABLE_PERIOD, signer);
        delete self._values[signer];
    }

    /// @notice Check if the map contains an operator
    /// @param self The OperatorMap
    /// @param signer The address of the operator
    /// @return True if the operator exists in the map, false otherwise
    function contains(OperatorMap storage self, address signer) internal view returns (bool) {
        return self._keys.contains(signer);
    }

    /// @notice Get the number of operators in the map
    /// @param self The OperatorMap
    /// @return The number of operators
    function length(
        OperatorMap storage self
    ) internal view returns (uint256) {
        return self._keys.length();
    }

    /// @notice Get all the operators in the map (whether they are active or not)
    /// @param self The OperatorMap
    /// @return The array of operators
    function getAll(
        OperatorMap storage self
    ) internal view returns (Operator[] memory) {
        Operator[] memory operators = new Operator[](self._keys.length());

        for (uint256 i = 0; i < self._keys.length(); i++) {
            // We ignore the enabledAt and disabledAt timestamps
            (address key,,) = self._keys.at(i);
            operators[i] = self._values[key];
        }

        return operators;
    }

    /// @notice Get all the currently active operators in the map
    /// @param self The OperatorMap
    /// @return The array of active operators
    function getAllActive(
        OperatorMap storage self
    ) internal view returns (Operator[] memory) {
        address[] memory keys = self._keys.getActive(Time.timestamp());
        Operator[] memory operators = new Operator[](keys.length);

        for (uint256 i = 0; i < keys.length; i++) {
            operators[i] = self._values[keys[i]];
        }

        return operators;
    }

    /// @notice Get an operator from the map, and whether it is currently active
    /// @param self The OperatorMap
    /// @param signer The address of the operator
    /// @return operator The operator struct, and whether it is currently active
    function get(
        OperatorMap storage self,
        address signer
    ) internal view returns (Operator memory operator, bool isActive) {
        require(self._keys.contains(signer), "Operator does not exist");
        isActive = self._keys.wasActiveAt(Time.timestamp(), signer);
        operator = self._values[signer];
    }

    /// @notice Update the rpc endpoint of an operator
    /// @param self The OperatorMap
    /// @param signer The address of the operator
    /// @param newRpcEndpoint The new rpc endpoint
    function updateRpcEndpoint(OperatorMap storage self, address signer, string memory newRpcEndpoint) internal {
        require(self._keys.contains(signer), "Operator does not exist");

        Operator storage operator = self._values[signer];
        operator.rpcEndpoint = newRpcEndpoint;
    }
}
