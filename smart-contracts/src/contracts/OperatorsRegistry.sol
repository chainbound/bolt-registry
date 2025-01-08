// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title OperatorsRegistry
/// @notice A smart contract to store and manage Bolt operators
contract OperatorsRegistry is OwnableUpgradeable, UUPSUpgradeable {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Operator struct
    struct Operator {
        address signer;
        string rpcEndpoint;
        address restakingMiddleware;
    }

    /// @notice A map of operators with their signer address as the key
    struct OperatorMap {
        EnumerableSet.Bytes32Set _keys;
        mapping(bytes32 key => Operator) _values;
    }

    /// @notice The set of bolt operators indexed by their signer address
    OperatorMap private OPERATORS;

    /// @notice The set of restaking middleware contract addresses
    AddressSet private RESTAKING_MIDDLEWARES;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     * This can be validated with the Openzeppelin Foundry Upgrades toolkit.
     *
     * Total storage slots: 50
     */
    uint256[48] private __gap;

    /// @notice Emitted when a new operator is added
    /// @param signer The address of the operator
    /// @param rpcEndpoint The rpc endpoint of the operator
    /// @param restakingMiddleware The address of the restaking middleware
    event OperatorAdded(address signer, string rpcEndpoint, address restakingMiddleware);

    /// @notice Initialize the contract
    function initialize(
        address owner
    ) public initializer {
        __Ownable_init(owner);
    }

    /// @notice Initialize the contract
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    // === Operators ===

    /// @notice Add an operator to the registry
    /// @param signer The address of the operator
    /// @param rpcEndpoint The rpc endpoint of the operator
    /// @param restakingMiddleware The address of the restaking middleware
    function addOperator(address signer, string memory rpcEndpoint, address restakingMiddleware) public {
        bytes32 key = bytes32(uint256(uint160(signer)));
        require(!OPERATORS._keys.contains(key), "Operator already exists");

        require(signer != address(0), "Invalid operator address");
        require(bytes(rpcEndpoint).length > 0, "Invalid rpc endpoint");
        require(restakingMiddlewares.contains(restakingMiddleware), "Invalid restaking middleware");

        OPERATORS._keys.add(key);
        OPERATORS._values[key] = Operator(signer, rpcEndpoint, restakingMiddleware);
        emit OperatorAdded(signer, rpcEndpoint, restakingMiddleware);
    }

    /// @notice Returns all the operators saved in the registry
    /// @return operators The array of operators
    function getAllOperators() public view returns (Operator[] memory operators) {
        uint256 length = OPERATORS._keys.length();
        Operator[] memory _operators = new Operator[](length);
        for (uint256 i = 0; i < length; i++) {
            bytes32 key = OPERATORS._keys.at(i);
            _operators[i] = OPERATORS._values[key];
        }
        return _operators;
    }

    /// @notice Returns the operator with the given signer address
    /// @param signer The address of the operator
    /// @return operator The operator struct
    function getOperator(
        address signer
    ) public view returns (Operator memory operator) {
        bytes32 key = bytes32(uint256(uint160(signer)));
        return OPERATORS._values[key];
    }

    // === Restaking Middlewres ===

    /// @notice Add a restaking middleware contract address to the registry
    /// @param middleware The address of the restaking middleware
    function addRestakingMiddleware(
        address middleware
    ) public onlyOwner {
        require(middleware != address(0), "Invalid middleware address");
        RESTAKING_MIDDLEWARES.add(middleware);
    }

    /// @notice Returns the addresses of the middleware contracts of restaking middlewares supported by Bolt.
    /// @return middlewares The array of middleware addresses
    function getSupportedRestakingMiddlewares() public view returns (address[] memory middlewares) {
        return RESTAKING_MIDDLEWARES.values();
    }
}
