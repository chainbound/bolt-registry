// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IOperatorsRegistryV1} from "../interfaces/IOperatorsRegistryV1.sol";

/// @title OperatorsRegistryV1
/// @notice A smart contract to store and manage Bolt operators
contract OperatorsRegistryV1 is OwnableUpgradeable, UUPSUpgradeable, IOperatorsRegistryV1 {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice The set of bolt operators indexed by their signer address
    OperatorMap private OPERATORS;

    /// @notice The mapping of restaking protocols to their middleware contract addresses
    mapping(RestakingProtocol => address) private RESTAKING_MIDDLEWARES;

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
    function initialize(
        address owner
    ) public initializer {
        __Ownable_init(owner);
    }

    /// @notice Upgrade the contract
    /// @param newImplementation The address of the new implementation
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    // ========= Operators functions ========= //

    /// @notice Register an operator in the registry
    /// @param signer The address of the operator
    /// @param rpcEndpoint The rpc endpoint of the operator
    /// @param restakingProtocol The identifier of the restaking protocol used to register
    function registerOperator(address signer, string memory rpcEndpoint, RestakingProtocol restakingProtocol) public {
        require(!OPERATORS._keys.contains(signer), "Operator already exists");

        require(signer != address(0), "Invalid operator address");
        require(bytes(rpcEndpoint).length > 0, "Invalid rpc endpoint");

        address restakingMiddleware = RESTAKING_MIDDLEWARES[restakingProtocol];
        require(restakingMiddleware != address(0), "Invalid restaking protocol");

        // Validate the operator by calling the middleware
        // IBoltRestakingMiddleware(restakingMiddleware).validateOperator(signer);

        OPERATORS._keys.add(signer);
        OPERATORS._values[signer] = Operator(signer, rpcEndpoint, restakingMiddleware);
        emit OperatorRegistered(signer, rpcEndpoint, restakingMiddleware);
    }

    /// @notice Returns all the operators saved in the registry
    /// @return operators The array of operators
    function getAllOperators() public view returns (Operator[] memory operators) {
        uint256 length = OPERATORS._keys.length();
        Operator[] memory _operators = new Operator[](length);
        for (uint256 i = 0; i < length; i++) {
            address key = OPERATORS._keys.at(i);
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
        return OPERATORS._values[signer];
    }

    /// @notice Returns true if the given address is an operator in the registry
    /// @param signer The address of the operator
    /// @return isOperator True if the address is an operator, false otherwise
    function isOperator(
        address signer
    ) public view returns (bool) {
        return OPERATORS._keys.contains(signer);
    }

    // ========= Restaking Middlewres ========= //

    /// @notice Update the address of a restaking middleware contract address
    /// @param restakingProtocol The identifier of the restaking protocol
    /// @param middleware The address of the new restaking middleware
    function updateRestakingMiddleware(RestakingProtocol restakingProtocol, address middleware) public onlyOwner {
        require(middleware != address(0), "Invalid middleware address");
        RESTAKING_MIDDLEWARES[restakingProtocol] = middleware;
    }

    /// @notice Returns the address of the restaking middleware for the given restaking protocol
    /// @param restakingProtocol The identifier of the restaking protocol
    /// @return middleware The address of the restaking middleware
    function getRestakingMiddleware(
        RestakingProtocol restakingProtocol
    ) public view returns (address middleware) {
        return RESTAKING_MIDDLEWARES[restakingProtocol];
    }
}
