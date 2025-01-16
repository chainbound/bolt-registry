// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

library OperatorsLibV1 {
    using EnumerableSet for EnumerableSet.AddressSet;

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

    /// @notice Add an operator to the map
    /// @param self The OperatorMap
    /// @param signer The address of the operator
    /// @param rpcEndpoint The rpc endpoint of the operator
    /// @param restakingMiddleware The address of the restaking middleware
    function add(
        OperatorMap storage self,
        address signer,
        string memory rpcEndpoint,
        address restakingMiddleware
    ) internal {
        require(!self._keys.contains(signer), "Operator already exists");

        require(signer != address(0), "Invalid operator address");
        require(bytes(rpcEndpoint).length > 0, "Invalid rpc endpoint");

        self._keys.add(signer);
        self._values[signer] = Operator(signer, rpcEndpoint, restakingMiddleware);
    }

    /// @notice Remove an operator from the map
    /// @param self The OperatorMap
    /// @param signer The address of the operator
    function remove(OperatorMap storage self, address signer) internal {
        require(self._keys.contains(signer), "Operator does not exist");

        self._keys.remove(signer);
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

    /// @notice Get all the operators in the map
    /// @param self The OperatorMap
    /// @return The array of operators
    function getAll(
        OperatorMap storage self
    ) internal view returns (Operator[] memory) {
        Operator[] memory operators = new Operator[](self._keys.length());

        for (uint256 i = 0; i < self._keys.length(); i++) {
            address key = self._keys.at(i);
            operators[i] = self._values[key];
        }

        return operators;
    }

    /// @notice Get an operator from the map
    /// @param self The OperatorMap
    /// @param signer The address of the operator
    /// @return The operator struct
    function get(OperatorMap storage self, address signer) internal view returns (Operator memory) {
        require(self._keys.contains(signer), "Operator does not exist");

        return self._values[signer];
    }
}
