// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin-v5.0.0/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Time} from "@openzeppelin-v5.0.0/contracts/utils/types/Time.sol";

import {PauseableEnumerableSet} from "@symbiotic/middleware-sdk/libraries/PauseableEnumerableSet.sol";

import {IOperatorsRegistryV2} from "../interfaces/IOperatorsRegistryV2.sol";
import {IRestakingMiddlewareV1} from "../interfaces/IRestakingMiddlewareV1.sol";

/// @title OperatorsRegistryV2
/// @author Chainbound Developers <dev@chainbound.io>
/// @notice A smart contract to store and manage Bolt operators
contract OperatorsRegistryV2 is IOperatorsRegistryV2, OwnableUpgradeable, UUPSUpgradeable {
    using PauseableEnumerableSet for PauseableEnumerableSet.AddressSet;

    /// @notice The start timestamp of the contract, used as reference for time-based operations
    uint48 public START_TIMESTAMP;

    /// @notice The duration of an epoch in seconds, used for delaying opt-in/out operations
    uint48 public EPOCH_DURATION;

    /// @notice The set of bolt operator addresses.
    PauseableEnumerableSet.AddressSet private _operatorAddresses;

    /// @notice The map of operators, with their operator address as the key
    mapping(address => Operator) public operators;

    /// @notice the address of the EigenLayer restaking middleware
    IRestakingMiddlewareV1 public EIGENLAYER_RESTAKING_MIDDLEWARE;

    /// @notice The address of the Symbiotic restaking middleware
    IRestakingMiddlewareV1 public SYMBIOTIC_RESTAKING_MIDDLEWARE;

    /// @notice The map of operators to their set of authorized signers
    mapping(address => PauseableEnumerableSet.AddressSet) private _authorizedSignersByOperator;

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting down storage in the inheritance chain.
    /// See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
    /// This can be validated with the Openzeppelin Foundry Upgrades toolkit.
    ///
    /// Total storage slots: 50
    uint256[43] private __gap;

    // ===================== ERRORS ======================== //

    error InvalidRpc();
    error InvalidOperator();
    error Unauthorized();
    error UnknownOperator();
    error OnlyRestakingMiddlewares();
    error UnknownSigner();
    error InvalidSigner();
    error InvalidMiddleware(string reason);

    // ========= Initializer & Proxy functionality ========= //

    /// @notice Initialize the contract
    /// @param owner The address of the owner
    function initialize(address owner, uint48 epochDuration) public initializer {
        __Ownable_init(owner);

        EPOCH_DURATION = epochDuration;
        START_TIMESTAMP = Time.timestamp();
    }

    /// @notice Re-initialize the contract after an upgrade
    /// @param owner The address of the owner
    function initializeV2(
        address owner
    ) public reinitializer(2) {
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
            OnlyRestakingMiddlewares()
        );
        _;
    }

    // ========= Public helpers ========= //

    /// @notice Returns the timestamp of when the current epoch started
    /// @return timestamp The timestamp of the current epoch start
    function getCurrentEpochStartTimestamp() public view returns (uint48) {
        uint48 currentEpoch = (Time.timestamp() - START_TIMESTAMP) / EPOCH_DURATION;
        return START_TIMESTAMP + currentEpoch * EPOCH_DURATION;
    }

    /// @notice Returns the timestamp of when the next epoch starts
    /// @return timestamp The timestamp of the next epoch start
    function getNextEpochStartTimestamp() public view returns (uint48) {
        return getCurrentEpochStartTimestamp() + EPOCH_DURATION;
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
    /// @param operator The address of the operator
    /// @param rpcEndpoint The rpc endpoint of the operator
    /// @param extraData Arbitrary data the operator can provide as part of registration
    /// @param authorizedSigners The addresses authorized to sign commitment on behalf of the operator.
    function registerOperator(
        address operator,
        string memory rpcEndpoint,
        string memory extraData,
        address[] memory authorizedSigners
    ) external onlyMiddleware {
        require(bytes(rpcEndpoint).length > 0, InvalidRpc());
        require(operator != address(0), InvalidOperator());

        for (uint256 i = 0; i < authorizedSigners.length; i++) {
            require(authorizedSigners[i] != address(0), InvalidSigner());
        }

        uint48 time = Time.timestamp();

        // Consider the operator active from the current timestamp onwards.
        _operatorAddresses.register(time, operator);
        operators[operator] = Operator(operator, rpcEndpoint, msg.sender, extraData);

        // Register the authorized signers as active from the current timestamp onwards.
        for (uint256 i = 0; i < authorizedSigners.length; i++) {
            _authorizedSignersByOperator[operator].register(time, authorizedSigners[i]);
        }

        emit OperatorRegistered(operator, rpcEndpoint, msg.sender, extraData, authorizedSigners);
    }

    /// @notice Pause an operator in the registry
    /// @param operator The address of the operator
    /// @dev Only restaking middleware contracts can call this function.
    /// @dev Paused operators are considered "inactive" until they are unpaused.
    function pauseOperator(
        address operator
    ) external onlyMiddleware {
        require(_operatorAddresses.contains(operator), UnknownOperator());

        // Pause the operator at the end of the current epoch.
        // Operators are still considered active until the start of the next epoch.
        uint48 time = getCurrentEpochStartTimestamp() - 1;
        _operatorAddresses.pause(time, operator);
        emit OperatorPaused(operator, msg.sender);
    }

    /// @notice Unpause an operator in the registry, marking them as "active"
    /// @param operator The address of the operator
    /// @dev Only restaking middleware contracts can call this function
    /// @dev Operators need to be paused and wait for EPOCH_DURATION() before they can be deregistered.
    function unpauseOperator(
        address operator
    ) external onlyMiddleware {
        require(_operatorAddresses.contains(operator), UnknownOperator());

        // Unpause the operator at the start of the next epoch.
        // Operators are still considered paused until the end of the current epoch.
        uint48 time = getCurrentEpochStartTimestamp() - 1;
        _operatorAddresses.unpause(time, EPOCH_DURATION, operator);
        emit OperatorUnpaused(operator, msg.sender);
    }

    /// @notice Update the rpc endpoint of an operator
    /// @param operator The address of the operator
    /// @param newRpcEndpoint The new rpc endpoint
    /// @dev Only restaking middleware contracts can call this function
    function updateOperatorRpcEndpoint(address operator, string memory newRpcEndpoint) external onlyMiddleware {
        require(_operatorAddresses.contains(operator), UnknownOperator());
        require(bytes(newRpcEndpoint).length > 0, InvalidRpc());

        operators[operator].rpcEndpoint = newRpcEndpoint;
    }

    /// @notice Add an authorized signer to an operator
    /// @param operator The address of the operator
    /// @param signer The address of the new authorized signer
    /// @dev Only restaking middleware contracts can call this function
    function addOperatorAuthorizedSigner(address operator, address signer) external onlyMiddleware {
        require(_operatorAddresses.contains(operator), UnknownOperator());
        require(signer != address(0), InvalidSigner());

        // Register the signer as active from the current epoch onwards.
        uint48 time = getCurrentEpochStartTimestamp();
        _authorizedSignersByOperator[operator].register(time, signer);
    }

    /// @notice Pause an authorized signer from an operator
    /// @param operator The address of the operator
    /// @param signer The address of the signer
    /// @dev Only restaking middleware contracts can call this function
    function pauseOperatorAuthorizedSigner(address operator, address signer) external onlyMiddleware {
        require(_operatorAddresses.contains(operator), UnknownOperator());
        require(_authorizedSignersByOperator[operator].contains(signer), UnknownSigner());

        // Pause the signer from the next epoch onwards. This ensures that the signer must wait for
        // one full epoch before they aren't considered active anymore (to prevent trying to avoid
        // being slashed).
        uint48 time = getCurrentEpochStartTimestamp() - 1;
        _authorizedSignersByOperator[operator].pause(time, signer);
    }

    /// @notice Unpause an authorized signer from an operator
    /// @param operator The address of the operator
    /// @param signer The address of the signer
    /// @dev Only restaking middleware contracts can call this function
    function unpauseOperatorAuthorizedSigner(address operator, address signer) external onlyMiddleware {
        require(_operatorAddresses.contains(operator), UnknownOperator());
        require(_authorizedSignersByOperator[operator].contains(signer), UnknownSigner());

        uint48 time = getCurrentEpochStartTimestamp() - 1;
        _authorizedSignersByOperator[operator].unpause(time, EPOCH_DURATION, signer);
    }

    /// @notice Remove an authorized signer from an operator
    /// @param operator The address of the operator
    /// @param signer The address of the signer
    /// @dev Only restaking middleware contracts can call this function
    function removeOperatorAuthorizedSigner(address operator, address signer) external onlyMiddleware {
        require(_operatorAddresses.contains(operator), UnknownOperator());
        require(_authorizedSignersByOperator[operator].contains(signer), UnknownSigner());

        uint48 time = getCurrentEpochStartTimestamp() - 1;
        _authorizedSignersByOperator[operator].unregister(time, EPOCH_DURATION, signer);
    }

    /// @notice Deregister an operator from the registry
    /// @param operator The address of the operator
    /// @dev Only restaking middleware contracts can call this function
    /// @dev Operators need to be paused and wait for EPOCH_DURATION() before they can be deregistered.
    function deregisterOperator(
        address operator
    ) external onlyMiddleware {
        require(_operatorAddresses.contains(operator), UnknownOperator());

        // NOTE: we use the current epoch start timestamp - 1 to ensure that the operator is deregistered
        // at the end of the current epoch. If we didn't do this, we would have to wait until the next
        // epoch until the operator was actually deregistered.
        uint48 time = getCurrentEpochStartTimestamp() - 1;
        _operatorAddresses.unregister(time, EPOCH_DURATION, operator);
        delete operators[operator];
        delete _authorizedSignersByOperator[operator];

        emit OperatorDeregistered(operator, msg.sender);
    }

    /// @notice Returns all the operators saved in the registry, including inactive ones.
    /// @return operators The array of operators
    function getAllOperators() public view returns (Operator[] memory) {
        Operator[] memory ops = new Operator[](_operatorAddresses.length());

        for (uint256 i = 0; i < _operatorAddresses.length(); i++) {
            (address operator,,) = _operatorAddresses.at(i);
            ops[i] = operators[operator];
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
    /// @param operator The address of the operator
    /// @return op The operator struct
    /// @return isActive True if the operator is active, false otherwise.
    /// @return authorizedSigners The authorized signers of the operator
    /// @dev Reverts if the operator does not exist
    function getOperator(
        address operator
    ) public view returns (Operator memory op, bool isActive, address[] memory authorizedSigners) {
        require(_operatorAddresses.contains(operator), UnknownOperator());

        op = operators[operator];
        isActive = _operatorAddresses.wasActiveAt(Time.timestamp(), operator);
        authorizedSigners = _authorizedSignersByOperator[operator].getActive(Time.timestamp());
    }

    /// @notice Returns true if the given address is an operator in the registry.
    /// @param operator The address of the operator.
    /// @return isOperator True if the address is an operator, false otherwise.
    function isOperator(
        address operator
    ) public view returns (bool) {
        return _operatorAddresses.contains(operator);
    }

    /// @notice Returns true if the given operator is registered AND active.
    /// @param operator The address of the operator
    /// @return isActiveOperator True if the operator is active, false otherwise.
    function isActiveOperator(
        address operator
    ) public view returns (bool) {
        return _operatorAddresses.wasActiveAt(Time.timestamp(), operator);
    }

    /// @notice Returns the operator that has the given signer address as an authorized signer.
    /// @param signerAddress The address of the signer.
    /// @return op The operator struct.
    /// @dev Reverts if no operator was found with the given signer address.
    function getOperatorFromSignerAddress(
        address signerAddress
    ) public view returns (Operator memory op) {
        // each operator can optionally have a list of authorized signers to make commitments on its behalf.
        // we find the operator that has signerAddress in its authorized signers list.
        for (uint256 i = 0; i < _operatorAddresses.length(); i++) {
            (address operator,,) = _operatorAddresses.at(i);
            if (_authorizedSignersByOperator[operator].contains(signerAddress)) {
                return operators[operator];
            }
        }

        revert UnknownOperator();
    }

    /// @notice Cleans up any expired operators (i.e. paused + EPOCH_DURATION has passed).
    function cleanup() public {
        for (uint256 i = 0; i < _operatorAddresses.length(); i++) {
            (address operator,,) = _operatorAddresses.at(i);
            if (_operatorAddresses.checkUnregister(Time.timestamp(), EPOCH_DURATION, operator)) {
                _operatorAddresses.unregister(Time.timestamp(), EPOCH_DURATION, operator);
                delete operators[operator];

                emit OperatorDeregistered(operator, msg.sender);
            }
        }
    }

    // ========= Restaking Middlewres ========= //

    /// @notice Update the address of a restaking middleware contract address
    /// @param restakingProtocol The name of the restaking protocol
    /// @param newMiddleware The address of the new restaking middleware
    function updateRestakingMiddleware(
        string calldata restakingProtocol,
        IRestakingMiddlewareV1 newMiddleware
    ) public onlyOwner {
        require(address(newMiddleware) != address(0), InvalidMiddleware("Middleware address cannot be 0"));

        bytes32 protocolNameHash = keccak256(abi.encodePacked(restakingProtocol));

        if (protocolNameHash == keccak256("EIGENLAYER")) {
            EIGENLAYER_RESTAKING_MIDDLEWARE = newMiddleware;
        } else if (protocolNameHash == keccak256("SYMBIOTIC")) {
            SYMBIOTIC_RESTAKING_MIDDLEWARE = newMiddleware;
        } else {
            revert InvalidMiddleware("Unknown restaking protocol, want EIGENLAYER or SYMBIOTIC");
        }
    }

    /// @notice Check if a map entry was active at a given timestamp.
    /// @param enabledTime The enabled time of the map entry.
    /// @param disabledTime The disabled time of the map entry.
    /// @param timestamp The timestamp to check the map entry status at.
    /// @return True if the map entry was active at the given timestamp, false otherwise.
    function _wasEnabledAt(uint48 enabledTime, uint48 disabledTime, uint48 timestamp) private pure returns (bool) {
        return enabledTime != 0 && enabledTime <= timestamp && (disabledTime == 0 || disabledTime >= timestamp);
    }
}
