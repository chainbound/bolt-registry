// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

import {PauseableEnumerableSet} from "@symbiotic/middleware-sdk/libraries/PauseableEnumerableSet.sol";

import {IOperatorsRegistryV1} from "../interfaces/IOperatorsRegistryV1.sol";
import {IBoltRestakingMiddlewareV1} from "../interfaces/IBoltRestakingMiddlewareV1.sol";

/// @title OperatorsRegistryV1
/// @notice A smart contract to store and manage Bolt operators
contract OperatorsRegistryV1 is IOperatorsRegistryV1, OwnableUpgradeable, UUPSUpgradeable {
    using PauseableEnumerableSet for PauseableEnumerableSet.AddressSet;

    /// @notice The start timestamp of the contract, used as reference for time-based operations
    uint48 public START_TIMESTAMP;

    /// @notice The duration of an epoch in seconds, used for delaying opt-in/out operations
    uint48 public EPOCH_DURATION;

    /// @notice The set of bolt operator addresses.
    PauseableEnumerableSet.AddressSet private _operatorAddresses;

    /// @notice The map of operators with their signer address as the key
    mapping(address => Operator) public operators;

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
    uint256[44] private __gap;

    // ========= Initializer & Proxy functionality ========= //

    /// @notice Initialize the contract
    /// @param owner The address of the owner
    function initialize(address owner, uint48 epochDuration) public initializer {
        __Ownable_init(owner);

        START_TIMESTAMP = Time.timestamp();
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
            "Only restaking middlewares can call this function"
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
    /// @param extraData Arbitrary data the operator can provide as part of registration
    function registerOperator(
        address signer,
        string memory rpcEndpoint,
        string memory extraData
    ) external onlyMiddleware {
        // TODO: Checks

        // TODO: should the enable timestamp here be the epoch instead?
        _operatorAddresses.register(Time.timestamp(), signer);
        operators[signer] = Operator(signer, rpcEndpoint, msg.sender, extraData);

        emit OperatorRegistered(signer, rpcEndpoint, msg.sender, extraData);
    }

    /// @notice Pause an operator in the registry
    /// @param signer The address of the operator
    /// @dev Only restaking middleware contracts can call this function.
    /// @dev Paused operators are considered "inactive" until they are unpaused.
    function pauseOperator(
        address signer
    ) external onlyMiddleware {
        _operatorAddresses.pause(EPOCH_DURATION, signer);
        emit OperatorPaused(signer, msg.sender);
    }

    /// @notice Unpause an operator in the registry, marking them as "active"
    /// @param signer The address of the operator
    /// @dev Only restaking middleware contracts can call this function
    /// @dev Operators need to be paused and wait for EPOCH_DURATION() before they can be deregistered.
    function unpauseOperator(
        address signer
    ) external onlyMiddleware {
        _operatorAddresses.unpause(Time.timestamp(), EPOCH_DURATION, signer);
        emit OperatorUnpaused(signer, msg.sender);
    }

    /// @notice Update the rpc endpoint of an operator
    /// @param signer The address of the operator
    /// @param newRpcEndpoint The new rpc endpoint
    /// @dev Only restaking middleware contracts can call this function
    function updateOperatorRpcEndpoint(address signer, string memory newRpcEndpoint) external onlyMiddleware {
        if (_operatorAddresses.contains(signer)) {
            operators[signer].rpcEndpoint = newRpcEndpoint;
        }
    }

    /// @notice Deregister an operator from the registry
    /// @param signer The address of the operator
    /// @dev Only restaking middleware contracts can call this function
    /// @dev Operators need to be paused and wait for IMMUTABLE_PERIOD() before they can be deregistered.
    function deregisterOperator(
        address signer
    ) external onlyMiddleware {
        _operatorAddresses.unregister(Time.timestamp(), EPOCH_DURATION, signer);
        delete operators[signer];

        emit OperatorDeregistered(signer, msg.sender);
    }

    /// @notice Returns all the operators saved in the registry, including inactive ones.
    /// @return operators The array of operators
    function getAllOperators() public view returns (Operator[] memory) {
        Operator[] memory ops = new Operator[](_operatorAddresses.length());

        for (uint256 i = 0; i < _operatorAddresses.length(); i++) {
            (address signer,,) = _operatorAddresses.at(i);
            ops[i] = operators[signer];
        }

        return ops;
    }

    /// @notice Returns the active operators in the registry.
    /// @return operators The array of active operators.
    function getActiveOperators() public view returns (Operator[] memory) {
        address[] memory addrs = _operatorAddresses.getActive(Time.timestamp());

        Operator[] memory ops = new Operator[](addrs.length);
        for (uint256 i = 0; i < addrs.length; i++) {
            ops[i] = operators[addrs[i]];
        }

        return ops;
    }

    /// @notice Returns the operator with the given signer address, and whether the operator is active
    /// @param signer The address of the operator
    /// @return operator The operator struct and a boolean indicating if the operator is active
    /// @dev Reverts if the operator does not exist
    function getOperator(
        address signer
    ) public view returns (Operator memory operator, bool isActive) {
        if (!_operatorAddresses.contains(signer)) {
            revert("Operator does not exist");
        }

        operator = operators[signer];

        return (operator, _operatorAddresses.wasActiveAt(Time.timestamp(), signer));
    }

    /// @notice Returns true if the given address is an operator in the registry.
    /// @param signer The address of the operator.
    /// @return isOperator True if the address is an operator, false otherwise.
    function isOperator(
        address signer
    ) public view returns (bool) {
        return _operatorAddresses.contains(signer);
    }

    /// @notice Returns true if the given operator is registered AND active.
    /// @param signer The address of the operator
    /// @return isActiveOperator True if the operator is active, false otherwise.
    function isActiveOperator(
        address signer
    ) public view returns (bool) {
        return _operatorAddresses.wasActiveAt(Time.timestamp(), signer);
    }

    // ========= Restaking Middlewres ========= //

    /// @notice Update the address of a restaking middleware contract address
    /// @param restakingProtocol The name of the restaking protocol
    /// @param newMiddleware The address of the new restaking middleware
    function updateRestakingMiddleware(
        string calldata restakingProtocol,
        IBoltRestakingMiddlewareV1 newMiddleware
    ) public onlyOwner {
        require(address(newMiddleware) != address(0), "Invalid middleware address");

        bytes32 protocolNameHash = keccak256(abi.encodePacked(restakingProtocol));

        if (protocolNameHash == keccak256("EIGENLAYER")) {
            EIGENLAYER_RESTAKING_MIDDLEWARE = newMiddleware;
        } else if (protocolNameHash == keccak256("SYMBIOTIC")) {
            SYMBIOTIC_RESTAKING_MIDDLEWARE = newMiddleware;
        } else {
            revert("Invalid restaking protocol name. Valid values are: 'EIGENLAYER', 'SYMBIOTIC'");
        }
    }
}
