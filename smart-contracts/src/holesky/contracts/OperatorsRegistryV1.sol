// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {IOperatorsRegistryV1} from "../interfaces/IOperatorsRegistryV1.sol";
import {IBoltResakingMiddlewareV1} from "../interfaces/IBoltResakingMiddlewareV1.sol";
import {OperatorsLibV1} from "../lib/OperatorsLibV1.sol";

/// @title OperatorsRegistryV1
/// @notice A smart contract to store and manage Bolt operators
contract OperatorsRegistryV1 is OwnableUpgradeable, UUPSUpgradeable, IOperatorsRegistryV1 {
    using OperatorsLibV1 for OperatorsLibV1.OperatorMap;

    /// @notice The set of bolt operators, indexed by their signer address
    OperatorsLibV1.OperatorMap private OPERATORS;

    /// @notice the address of the EigenLayer restaking middleware
    address public EIGENLAYER_RESTAKING_MIDDLEWARE;

    /// @notice The address of the Symbiotic restaking middleware
    address public SYMBIOTIC_RESTAKING_MIDDLEWARE;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     * This can be validated with the Openzeppelin Foundry Upgrades toolkit.
     *
     * Total storage slots: 50
     */
    uint256[45] private __gap;

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

    // ========= Modifiers ========= //

    /// @notice Only one of the middleware contracts can call the function
    modifier onlyMiddleware() {
        require(
            msg.sender == address(EIGENLAYER_RESTAKING_MIDDLEWARE)
                || msg.sender == address(SYMBIOTIC_RESTAKING_MIDDLEWARE),
            "Only restaking middlewares can call this function"
        );
        _;
    }

    // ========= Operators functions ========= //

    /// @notice Register an operator in the registry
    /// @param signer The address of the operator
    /// @param rpcEndpoint The rpc endpoint of the operator
    /// @dev Only restaking middleware contracts can call this function
    function registerOperator(address signer, string memory rpcEndpoint) external onlyMiddleware {
        require(!OPERATORS.contains(signer), "Operator already exists");

        OPERATORS.add(signer, rpcEndpoint, msg.sender);
        emit OperatorRegistered(signer, rpcEndpoint, msg.sender);
    }

    /// @notice Returns all the operators saved in the registry
    /// @return operators The array of operators
    function getAllOperators() public view returns (Operator[] memory operators) {
        return OPERATORS.getAll();
    }

    /// @notice Returns the operator with the given signer address
    /// @param signer The address of the operator
    /// @return operator The operator struct
    /// @dev Reverts if the operator does not exist
    function getOperator(
        address signer
    ) public view returns (Operator memory operator) {
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
    /// @param restakingProtocol The identifier of the restaking protocol
    /// @param middleware The address of the new restaking middleware
    function updateRestakingMiddleware(string restakingProtocol, address newMiddleware) public onlyOwner {
        require(newMiddleware != address(0), "Invalid middleware address");

        if (restakingProtocol == "EIGENLAYER") {
            EIGENLAYER_RESTAKING_MIDDLEWARE = newMiddleware;
        } else if (restakingProtocol == "SYMBIOTIC") {
            SYMBIOTIC_RESTAKING_MIDDLEWARE = newMiddleware;
        } else {
            revert("Invalid restaking protocol name. Valid values are: 'EIGENLAYER', 'SYMBIOTIC'");
        }
    }
}
