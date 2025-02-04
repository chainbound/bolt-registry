// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin-v5.0.0/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Time} from "@openzeppelin-v5.0.0/contracts/utils/types/Time.sol";

import {PauseableEnumerableSet} from "@symbiotic/middleware-sdk/libraries/PauseableEnumerableSet.sol";

import {
    IAllocationManager, IAllocationManagerTypes
} from "@eigenlayer/src/contracts/interfaces/IAllocationManager.sol";
import {ISignatureUtils} from "@eigenlayer/src/contracts/interfaces/ISignatureUtils.sol";
import {IDelegationManager} from "@eigenlayer/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "@eigenlayer/src/contracts/interfaces/IStrategyManager.sol";
import {IAVSDirectory} from "@eigenlayer/src/contracts/interfaces/IAVSDirectory.sol";
import {IAVSRegistrar} from "@eigenlayer/src/contracts/interfaces/IAVSRegistrar.sol";
import {IStrategy} from "@eigenlayer/src/contracts/interfaces/IStrategy.sol";

import {IRestakingMiddlewareV1} from "../interfaces/IRestakingMiddlewareV1.sol";
import {IOperatorsRegistryV2} from "../interfaces/IOperatorsRegistryV2.sol";

/**
 * @title BoltEigenLayerMiddlewareV4
 * @author Chainbound Developers <dev@chainbound.io>
 * @notice This contract is responsible for interacting with the EigenLayer restaking protocol contracts. It serves
 *         as AVS contract and implements the IAVSRegistrar interface as well.
 */
contract EigenLayerMiddlewareV4 is OwnableUpgradeable, UUPSUpgradeable, IAVSRegistrar, IRestakingMiddlewareV1 {
    using PauseableEnumerableSet for PauseableEnumerableSet.AddressSet;

    /// @notice Address of the EigenLayer AVS Directory contract.
    IAVSDirectory public AVS_DIRECTORY;

    /// @notice Address of the EigenLayer Allocation Manager contract.
    IAllocationManager public ALLOCATION_MANAGER;

    /// @notice Address of the EigenLayer Delegation Manager contract.
    IDelegationManager public DELEGATION_MANAGER;

    /// @notice Address of the EigenLayer Strategy Manager contract.
    IStrategyManager public STRATEGY_MANAGER;

    /// @notice Address of the Bolt Operators Registry contract.
    IOperatorsRegistryV2 public OPERATORS_REGISTRY;

    /// @notice The name of the middleware
    bytes32 public NAME_HASH;

    /// @notice The list of whitelisted strategies for this AVS
    PauseableEnumerableSet.AddressSet internal _strategyWhitelist;

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting down storage in the inheritance chain.
    /// See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
    /// This can be validated with the Openzeppelin Foundry Upgrades toolkit.
    ///
    /// Total storage slots: 50
    uint256[42] private __gap;

    // ========= Events ========= //

    /// @notice Emitted when a strategy is whitelisted
    event StrategyWhitelisted(address indexed strategy);

    /// @notice Emitted when a strategy is removed from the whitelist
    event StrategyRemoved(address indexed strategy);

    /// @notice Emitted when a strategy is paused
    event StrategyPaused(address indexed strategy);

    /// @notice Emitted when a strategy is unpaused
    event StrategyUnpaused(address indexed strategy);

    // ========= Errors ========= //

    error NotOperator();
    error UnauthorizedStrategy();
    error NotAllocationManager();
    error InvalidStrategyAddress();
    error StrategyAlreadyWhitelisted();

    // ========= Initializer & Proxy functionality ========= //

    /// @notice Initialize the contract
    /// @param owner The address of the owner
    /// @param _avsDirectory The address of the EigenLayer AVS Directory contract
    /// @param _eigenlayerAllocationManager The address of the EigenLayer Allocation Manager contract
    /// @param _eigenlayerDelegationManager The address of the EigenLayer Delegation Manager contract
    /// @param _eigenlayerStrategyManager The address of the EigenLayer Strategy Manager contract
    /// @param _operatorsRegistry The address of the Operators Registry contract
    function initialize(
        address owner,
        IOperatorsRegistryV2 _operatorsRegistry,
        IAVSDirectory _avsDirectory,
        IAllocationManager _eigenlayerAllocationManager,
        IDelegationManager _eigenlayerDelegationManager,
        IStrategyManager _eigenlayerStrategyManager
    ) public initializer {
        __Ownable_init(owner);

        AVS_DIRECTORY = _avsDirectory;
        ALLOCATION_MANAGER = _eigenlayerAllocationManager;
        DELEGATION_MANAGER = _eigenlayerDelegationManager;
        STRATEGY_MANAGER = _eigenlayerStrategyManager;
        OPERATORS_REGISTRY = _operatorsRegistry;
        NAME_HASH = keccak256("EIGENLAYER");
    }

    /// @notice Re-Initialize the contract after the upgrade
    /// @param owner The address of the owner
    function initializeV4(
        address owner
    ) public reinitializer(4) {
        __Ownable_init(owner);
    }

    /// @notice Upgrade the contract
    /// @param newImplementation The address of the new implementation
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    // ========= Modifiers ========= //

    /// @notice Modifier to check if the caller is the AllocationManager
    modifier onlyAllocationManager() {
        require(msg.sender == address(ALLOCATION_MANAGER), NotAllocationManager());
        _;
    }

    // ========= AVS functions ========= //

    /// @notice Get the collaterals and amounts staked by an operator across the whitelisted strategies
    /// @param operator The operator address to get the collaterals and amounts staked for
    /// @return collaterals The collaterals staked by the operator
    /// @dev Assumes that the operator is registered and enabled
    function getOperatorCollaterals(
        address operator
    ) public view returns (address[] memory, uint256[] memory) {
        // Only take strategies that are currently active
        uint48 time = Time.timestamp();
        IStrategy[] memory activeStrategies = _getActiveStrategiesAt(time);

        address[] memory collateralTokens = new address[](activeStrategies.length);
        uint256[] memory amounts = new uint256[](activeStrategies.length);

        // get the shares of the operator across all strategies
        uint256[] memory shares = DELEGATION_MANAGER.getOperatorShares(operator, activeStrategies);

        // get the collateral tokens and amounts for the operator across all strategies
        for (uint256 i = 0; i < activeStrategies.length; i++) {
            collateralTokens[i] = address(activeStrategies[i].underlyingToken());
            amounts[i] = activeStrategies[i].sharesToUnderlyingView(shares[i]);
        }

        return (collateralTokens, amounts);
    }

    /// @notice Get the CURRENT amount staked by an operator for a specific collateral
    /// @param operator The operator address to get the amount staked for
    /// @param collateral The collateral token address
    /// @return The amount staked by the operator for the collateral
    function getOperatorStake(address operator, address collateral) public view returns (uint256) {
        // Only take strategies that are currently active
        uint48 time = Time.timestamp();

        uint256 activeStake = 0;
        for (uint256 i = 0; i < _strategyWhitelist.length(); i++) {
            (address strategy, uint48 enabledAt, uint48 disabledAt) = _strategyWhitelist.at(i);

            if (!_wasEnabledAt(enabledAt, disabledAt, time)) {
                continue;
            }

            if (address(IStrategy(strategy).underlyingToken()) != collateral) {
                continue;
            }

            // get the shares of the operator for the strategy
            // NOTE: the EL slashing-magnitudes branch removed the operatorShares(operator, strategy) function:
            // https://github.com/Layr-Labs/eigenlayer-contracts/blob/dev/src/contracts/interfaces/IDelegationManager.sol#L352-L359
            // so we need to use getOperatorShares(operator, [strategy]) instead.
            IStrategy[] memory strategies = new IStrategy[](1);
            strategies[0] = IStrategy(strategy);
            uint256[] memory shares = DELEGATION_MANAGER.getOperatorShares(operator, strategies);
            activeStake += IStrategy(strategy).sharesToUnderlyingView(shares[0]);
        }

        return activeStake;
    }

    /// @notice Unpause an operator
    /// @dev This function is used to unpause an operator that has been paused
    function unpauseOperator() public {
        address operator = msg.sender;

        OPERATORS_REGISTRY.unpauseOperator(operator);
    }

    // ========= Strategy queries ========= //

    /// @notice Get all whitelisted strategies for this AVS, including inactive ones.
    /// @return The list of whitelisted strategies
    function getWhitelistedStrategies() public view returns (address[] memory) {
        address[] memory strategies = new address[](_strategyWhitelist.length());

        for (uint256 i = 0; i < _strategyWhitelist.length(); i++) {
            (strategies[i],,) = _strategyWhitelist.at(i);
        }

        return strategies;
    }

    /// @notice Get the active strategies for this AVS
    /// @return The active strategies
    function getActiveWhitelistedStrategies() public view returns (IStrategy[] memory) {
        // get the strategies that are currently active
        uint48 time = Time.timestamp(); 
        return _getActiveStrategiesAt(time);
    }

    /// @notice Get the number of whitelisted strategies for this AVS.
    /// @return The number of whitelisted strategies.
    function strategyWhitelistLength() public view returns (uint256) {
        return _strategyWhitelist.length();
    }

    /// @notice Returns whether the strategy is active in this epoch.
    /// @param strategy The strategy to check.
    /// @return True if the strategy is active in this epoch, false otherwise.
    function isStrategyActive(
        address strategy
    ) public view returns (bool) {
        uint48 time = Time.timestamp();
        return _strategyWhitelist.wasActiveAt(time, strategy);
    }

    // ========= [pre-ELIP-002] IServiceManager functions ========= //

    /// @notice Register an operator through the AVS Directory
    /// @param rpcEndpoint The RPC URL of the operator
    /// @param extraData Arbitrary data the operator can provide as part of registration
    /// @param operatorSignature The signature of the operator
    /// @param authorizedSigners The addresses authorized to sign commitment on behalf of the operator.
    /// @dev This function is used before the ELIP-002 (slashing) EigenLayer upgrade to register operators.
    /// @dev Operators must use this function to register before the upgrade. After the upgrade, this will be removed.
    function registerOperatorToAVS(
        string memory rpcEndpoint,
        string memory extraData,
        ISignatureUtils.SignatureWithSaltAndExpiry calldata operatorSignature,
        address[] memory authorizedSigners
    ) public {
        address operator = msg.sender;

        require(DELEGATION_MANAGER.isOperator(operator), NotOperator());

        // The operator signature is checked in the AVS Directory contract
        AVS_DIRECTORY.registerOperatorToAVS(operator, operatorSignature);
        OPERATORS_REGISTRY.registerOperator(operator, rpcEndpoint, extraData, authorizedSigners);
    }

    /// @notice Deregister an operator through the AVS Directory
    /// @dev This function is used before the ELIP-002 (slashing) EigenLayer upgrade to deregister operators.
    /// @dev Operators must use this function to deregister before the upgrade. After the upgrade, this will be removed.
    function deregisterOperatorFromAVS() public {
        address operator = msg.sender;

        require(DELEGATION_MANAGER.isOperator(operator), NotOperator());

        AVS_DIRECTORY.deregisterOperatorFromAVS(operator);
        OPERATORS_REGISTRY.pauseOperator(operator);
    }

    /// @notice Update the metadata URI for this AVS
    /// @param contractName The name of the contract to update the metadata URI for
    /// @param metadataURI The new metadata URI
    function updateAVSMetadataURI(string calldata contractName, string calldata metadataURI) public onlyOwner {
        bytes32 contractNameHash = keccak256(abi.encodePacked(contractName));

        if (contractNameHash == keccak256("ALLOCATION_MANAGER")) {
            ALLOCATION_MANAGER.updateAVSMetadataURI(address(this), metadataURI);
        } else if (contractNameHash == keccak256("AVS_DIRECTORY")) {
            AVS_DIRECTORY.updateAVSMetadataURI(metadataURI);
        }
    }

    /// @notice Get the strategies that an operator has restaked in
    /// @param operator The operator address to get the restaked strategies for
    /// @return The restaked strategy addresses
    function getOperatorRestakedStrategies(
        address operator
    ) public view returns (address[] memory) {
        // get the strategies that are currently active
        uint48 time = Time.timestamp();
        IStrategy[] memory activeStrategies = _getActiveStrategiesAt(time);

        address[] memory restakedStrategies = new address[](activeStrategies.length);

        // get the shares of the operator across all strategies
        uint256[] memory shares = DELEGATION_MANAGER.getOperatorShares(operator, activeStrategies);

        // get the collateral tokens and amounts for the operator across all strategies
        uint256 restakedCount = 0;
        for (uint256 i = 0; i < activeStrategies.length; i++) {
            if (activeStrategies[i].sharesToUnderlyingView(shares[i]) > 0) {
                restakedStrategies[restakedCount] = address(activeStrategies[i]);
                restakedCount++;
            }
        }

        address[] memory result = new address[](restakedCount);
        for (uint256 i = 0; i < restakedCount; i++) {
            result[i] = restakedStrategies[i];
        }

        return result;
    }

    /// @notice Get the strategies that operators can restake in
    /// @return The restakeable strategy addresses
    function getRestakeableStrategies() public view returns (address[] memory) {
        // All operators can use all whitelisted, active strategies.
        IStrategy[] memory strategies = getActiveWhitelistedStrategies();

        // cast to address[] to match the return type
        address[] memory result = new address[](strategies.length);
        for (uint256 i = 0; i < strategies.length; i++) {
            result[i] = address(strategies[i]);
        }

        return result;
    }

    // ========= [post-ELIP-002] IAVSRegistrar functions ========= //

    /// @notice Allows the AllocationManager to hook into the middleware to validate operator registration
    /// @param operator The address of the operator
    /// @param operatorSetIds The operator set IDs the operator is registering for
    /// @param data Arbitrary ABI-encoded data the operator must provide as part of registration
    function registerOperator(
        address operator,
        uint32[] calldata operatorSetIds,
        bytes calldata data
    ) external onlyAllocationManager {
        // NOTE: this function is called by AllocationManager.registerForOperatorSets(),
        // called by operators when registering to this AVS. If this call reverts,
        // the registration will be unsuccessful.

        // Split the data into rpcEndpoint, extraData and authorizedSigners from ABI encoding
        (string memory rpcEndpoint, string memory extraData, address[] memory authorizedSigners) =
            abi.decode(data, (string, string, address[]));

        // We forward the call to the OperatorsRegistry to register the operator in its storage.
        OPERATORS_REGISTRY.registerOperator(operator, rpcEndpoint, extraData, authorizedSigners);
    }

    /// @notice Allows the AllocationManager to hook into the middleware to validate operator deregistration
    /// @param operator The address of the operator
    /// @param operatorSetIds The operator set IDs the operator is deregistering from
    function deregisterOperator(address operator, uint32[] calldata operatorSetIds) external onlyAllocationManager {
        // NOTE: this function is called by AllocationManager.deregisterFromOperatorSets,
        // called by operators when deregistering from this AVS.
        // Failure does nothing here: if this call reverts the deregistration will still go through.

        // We forward the call to the OperatorsRegistry to pause the operator from its storage.
        // In order to be fully removed, the operator must call OPERATORS_REGISTRY.deregisterOperator()
        // after waiting for the required delay.
        OPERATORS_REGISTRY.pauseOperator(operator);
    }

    // ========= Admin functions ========= //

    /// @notice Add a strategy to the whitelist
    /// @param strategy The strategy to add
    function whitelistStrategy(
        address strategy
    ) public onlyOwner {
        require(strategy != address(0), InvalidStrategyAddress());
        require(!_strategyWhitelist.contains(strategy), StrategyAlreadyWhitelisted());
        require(STRATEGY_MANAGER.strategyIsWhitelistedForDeposit(IStrategy(strategy)), UnauthorizedStrategy());

        uint48 time = Time.timestamp();
        _strategyWhitelist.register(time, strategy);
        emit StrategyWhitelisted(strategy);
    }

    /// @notice Pause a strategy, preventing its collateral from being active in the AVS
    /// @param strategy The strategy to pause
    function pauseStrategy(
        address strategy
    ) public onlyOwner {
        require(_strategyWhitelist.contains(strategy), UnauthorizedStrategy());

        // Pause the strategy at the end of the current epoch.
        // Strategies are still considered active until the start of the next epoch.
        uint48 time = OPERATORS_REGISTRY.getCurrentEpochStartTimestamp() - 1;
        _strategyWhitelist.pause(time, strategy);
        emit StrategyPaused(strategy);
    }

    /// @notice Unpause a strategy, allowing its collateral to be active in the AVS
    /// @param strategy The strategy to unpause
    function unpauseStrategy(
        address strategy
    ) public onlyOwner {
        require(_strategyWhitelist.contains(strategy), UnauthorizedStrategy());

        // Unpause the strategy at the start of the next epoch.
        // Strategies are still considered paused until the end of the current epoch.
        uint48 time = OPERATORS_REGISTRY.getCurrentEpochStartTimestamp() - 1;
        _strategyWhitelist.unpause(time, OPERATORS_REGISTRY.EPOCH_DURATION(), strategy);
        emit StrategyUnpaused(strategy);
    }

    /// @notice Remove a strategy from the whitelist
    /// @param strategy The strategy to remove
    /// @dev Strategies must be paused for an EPOCH_DURATION before they can be removed
    function removeStrategy(
        address strategy
    ) public onlyOwner {
        require(_strategyWhitelist.contains(strategy), UnauthorizedStrategy());

        // Remove the strategy in 1 epoch
        // Strategies must be paused for at least 1 epoch before they can be removed
        uint48 time = Time.timestamp();
        _strategyWhitelist.unregister(time, OPERATORS_REGISTRY.EPOCH_DURATION(), strategy);
        emit StrategyRemoved(strategy);
    }

    /// @notice Create new operator sets for this AVS
    /// @param params The parameters for creating the operator sets
    function createOperatorSets(
        IAllocationManagerTypes.CreateSetParams[] calldata params
    ) public onlyOwner {
        for (uint256 i = 0; i < params.length; i++) {
            _checkAreAllStrategiesWhitelisted(params[i].strategies);
        }

        ALLOCATION_MANAGER.createOperatorSets(address(this), params);
    }

    /// @notice Add strategies to an operator set
    /// @param operatorSetId The ID of the operator set to add strategies to
    /// @param strategies The strategies to add
    function addStrategiesToOperatorSet(uint32 operatorSetId, IStrategy[] calldata strategies) public onlyOwner {
        _checkAreAllStrategiesWhitelisted(strategies);

        ALLOCATION_MANAGER.addStrategiesToOperatorSet(address(this), operatorSetId, strategies);
    }

    /// @notice Remove strategies from an operator set
    /// @param operatorSetId The ID of the operator set to remove strategies from
    /// @param strategies The strategies to remove
    function removeStrategiesFromOperatorSet(uint32 operatorSetId, IStrategy[] calldata strategies) public onlyOwner {
        ALLOCATION_MANAGER.removeStrategiesFromOperatorSet(address(this), operatorSetId, strategies);
    }

    /// @notice Update the AllocationManager address
    /// @param newAllocationManager The new AllocationManager address
    function updateAllocationManagerAddress(
        address newAllocationManager
    ) public onlyOwner {
        ALLOCATION_MANAGER = IAllocationManager(newAllocationManager);
    }

    /// @notice Update the AVSDirectory address
    /// @param newAVSDirectory The new AVSDirectory address
    function updateAVSDirectoryAddress(
        address newAVSDirectory
    ) public onlyOwner {
        AVS_DIRECTORY = IAVSDirectory(newAVSDirectory);
    }

    /// @notice Update the StrategyManager address
    /// @param newStrategyManager The new StrategyManager address
    function updateStrategyManagerAddress(
        address newStrategyManager
    ) public onlyOwner {
        STRATEGY_MANAGER = IStrategyManager(newStrategyManager);
    }

    /// @notice Update the DelegationManager address
    /// @param newDelegationManager The new DelegationManager address
    function updateDelegationManagerAddress(
        address newDelegationManager
    ) public onlyOwner {
        DELEGATION_MANAGER = IDelegationManager(newDelegationManager);
    }

    /// @notice Update the OperatorsRegistry address
    /// @param newOperatorsRegistry The new OperatorsRegistry address
    function updateOperatorsRegistryAddress(
        address newOperatorsRegistry
    ) public onlyOwner {
        OPERATORS_REGISTRY = IOperatorsRegistryV2(newOperatorsRegistry);
    }

    // ========== Internal helpers ========== //

    /// @notice Check if ALL the given strategies are whitelisted.
    /// If any of the strategies are not whitelisted, the function will revert.
    /// @param strategies The strategies to check
    function _checkAreAllStrategiesWhitelisted(
        IStrategy[] calldata strategies
    ) internal view {
        for (uint256 i = 0; i < strategies.length; i++) {
            require(_strategyWhitelist.contains(address(strategies[i])), UnauthorizedStrategy());
        }
    }

    /// @notice Get all the active strategies at a given timestamp
    /// @param timestamp The timestamp to get the active strategies at
    /// @return The array of active strategies
    function _getActiveStrategiesAt(
        uint48 timestamp
    ) internal view returns (IStrategy[] memory) {
        uint256 activeCount = 0;
        address[] memory activeStrategies = new address[](_strategyWhitelist.length());
        for (uint256 i = 0; i < _strategyWhitelist.length(); i++) {
            (address strategy, uint48 enabledAt, uint48 disabledAt) = _strategyWhitelist.at(i);

            if (_wasEnabledAt(enabledAt, disabledAt, timestamp)) {
                activeStrategies[activeCount] = strategy;
                activeCount++;
            }
        }

        // Resize the array to the actual number of active strategies
        IStrategy[] memory result = new IStrategy[](activeCount);
        for (uint256 i = 0; i < activeCount; i++) {
            result[i] = IStrategy(activeStrategies[i]);
        }
        return result;
    }

    /// @notice Check if a map entry was active at a given timestamp.
    /// @param enabledAt The enabled time of the map entry.
    /// @param disabledAt The disabled time of the map entry.
    /// @param timestamp The timestamp to check the map entry status at.
    /// @return True if the map entry was active at the given timestamp, false otherwise.
    function _wasEnabledAt(uint48 enabledAt, uint48 disabledAt, uint48 timestamp) internal pure returns (bool) {
        return enabledAt != 0 && enabledAt <= timestamp && (disabledAt == 0 || disabledAt >= timestamp);
    }
}
