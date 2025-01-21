// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

import {IVault} from "@symbiotic/core/interfaces/vault/IVault.sol";
import {IVaultStorage} from "@symbiotic/core/interfaces/vault/IVaultStorage.sol";
import {IEntity} from "@symbiotic/core/interfaces/common/IEntity.sol";
import {IOperatorSpecificDelegator} from "@symbiotic/core/interfaces/delegator/IOperatorSpecificDelegator.sol";
import {IBaseDelegator} from "@symbiotic/core/interfaces/delegator/IBaseDelegator.sol";
import {IRegistry} from "@symbiotic/core/interfaces/common/IRegistry.sol";
import {IOptInService} from "@symbiotic/core/interfaces/service/IOptInService.sol";
import {Subnetwork} from "@symbiotic/core/contracts/libraries/Subnetwork.sol";
import {INetworkRegistry} from "@symbiotic/core/interfaces/INetworkRegistry.sol";
import {INetworkMiddlewareService} from "@symbiotic/core/interfaces/service/INetworkMiddlewareService.sol";

import {PauseableEnumerableSet} from "@symbiotic/middleware-sdk/libraries/PauseableEnumerableSet.sol";

import {IOperatorsRegistryV1} from "../interfaces/IOperatorsRegistryV1.sol";

/**
 * @title SymbioticMiddlewareV1
 * @author Chainbound Developers <dev@chainbound.io>
 * @notice This contract is responsible for interacting with the Symbiotic restaking protocol contracts. It is both
 *         the middleware and the actual network contract, because it self-registers with the network registry.
 *         Responsibilities include: operator and vault management, stake aggregation across multiple vaults, and in the
 *         future: slashing & rewards.
 * @dev This contract is based on the middleware-SDK.
 *
 * For more information on extensions, see <https://docs.symbiotic.fi/middleware-sdk/extensions>.
 * All public view functions are implemented in the `BaseMiddlewareReader`: <https://docs.symbiotic.fi/middleware-sdk/api-reference/middleware/BaseMiddlewareReader>
 */
contract BoltSymbioticMiddlewareV1 is OwnableUpgradeable, UUPSUpgradeable {
    using Subnetwork for address;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.AddressToAddressMap;
    using PauseableEnumerableSet for PauseableEnumerableSet.AddressSet;

    // ================ STORAGE ================== //
    //
    // Most of these constants replicate view methods in the BaseMiddlewareReader.
    // See <https://docs.symbiotic.fi/middleware-sdk/api-reference/middleware/BaseMiddlewareReader> for more information.

    /// @notice The timestamp of the first epoch (when this contract gets initialized).
    uint48 public START_TIMESTAMP;

    /// @notice The address of the bolt registry
    IOperatorsRegistryV1 public OPERATORS_REGISTRY;

    /// @notice The Symbiotic network: address(this)
    address public NETWORK;

    /// @notice The duration of the slashing window.
    uint48 public SLASHING_WINDOW;

    /// @notice The duration of an epoch.
    uint48 public EPOCH_DURATION;

    /// @notice The Symbiotic vault registry.
    address public VAULT_REGISTRY;

    /// @notice The Symbiotic operator registry.
    address public OPERATOR_REGISTRY;

    /// @notice The Symbiotic operator network opt-in service.
    address public OPERATOR_NET_OPTIN;

    /// @notice Default subnetwork.
    uint96 internal constant DEFAULT_SUBNETWORK = 0;

    /// @notice The set of whitelisted vaults for the network.
    PauseableEnumerableSet.AddressSet private _vaultWhitelist;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shift_initializeNetworkage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     * This can be validated with the Openzeppelin Foundry Upgrades toolkit.
     *
     * Total storage slots: 50
     */
    uint256[43] private __gap;

    /// @notice The vault delegator types.
    /// @dev <https://docs.symbiotic.fi/modules/vault/introduction#3-limits-and-delegation-logic-module>
    enum DelegatorType {
        // Shared vaults
        FULL_RESTAKE,
        NETWORK_RESTAKE,
        // Operator-specific vaults
        OPERATOR_SPECIFIC,
        OPERATOR_NETWORK_SPECIFIC
    }

    /// =================== EVENTS ====================== //
    event VaultPaused(address indexed vault);
    event VaultUnpaused(address indexed vault);
    event VaultWhitelisted(address indexed vault);
    event VaultRemoved(address indexed vault);

    /// =================== ERRORS ====================== //
    error NotOperator();
    error OperatorNotOptedIn();
    error OperatorNotRegistered();

    error NotVault();
    error VaultNotInitialized();
    error VaultAlreadyRegistered();
    error UnauthorizedVault();
    error NotOperatorSpecificVault();

    /// =================== MODIFIERS =================== //

    /**
     * @notice Constructor for initializing the SymbioticMiddlewareV1 contract
     * @param owner The address of the owner
     * @param network The address of the network
     * @param slashingWindow The duration of the slashing window (unused in V1)
     * @param vaultRegistry The address of the vault registry
     * @param operatorRegistry The address of the operator registry
     * @param operatorNetOptin The address of the operator network opt-in service
     * @dev We put all of the contract dependencies in the constructor to make it easier to (re-)deploy
     *      when dependencies are upgraded.
     */
    function initialize(
        address owner,
        address network,
        address boltOperatorsRegistry,
        uint48 epochDuration,
        uint48 slashingWindow,
        address vaultRegistry,
        address operatorRegistry,
        address operatorNetOptin
    ) public initializer {
        __Ownable_init(owner);

        NETWORK = network;
        OPERATORS_REGISTRY = IOperatorsRegistryV1(boltOperatorsRegistry);
        SLASHING_WINDOW = slashingWindow;
        EPOCH_DURATION = epochDuration;
        VAULT_REGISTRY = vaultRegistry;
        OPERATOR_REGISTRY = operatorRegistry;
        OPERATOR_NET_OPTIN = operatorNetOptin;
        START_TIMESTAMP = _now();
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    // ================ OPERATORS ===================== //
    //
    // These functions are only callable by the bolt registry.
    // All external operator management is done through the bolt registry.

    /**
     * @notice Register an operator in the registry.
     */
    function registerOperator(
        string calldata rpcEndpoint
    ) public {
        if (!IRegistry(OPERATOR_REGISTRY).isEntity(msg.sender)) {
            revert NotOperator();
        }

        if (!IOptInService(OPERATOR_NET_OPTIN).isOptedIn(msg.sender, NETWORK)) {
            revert OperatorNotOptedIn();
        }

        OPERATORS_REGISTRY.registerOperator(msg.sender, rpcEndpoint);
    }

    /**
     * @notice Deregister an operator from the registry.
     */
    function deregisterOperator() public {
        OPERATORS_REGISTRY.deregisterOperator(msg.sender);

        // TODO(V3): in the future we may not want to remove the vaults immediately, in case
        // of a pending penalty that the operator is trying to avoid.
    }

    /// @notice Update your RPC endpoint as an operator.
    /// @param rpcEndpoint The new rpc endpoint.
    function updateOperatorRpcEndpoint(
        string calldata rpcEndpoint
    ) public {
        OPERATORS_REGISTRY.updateOperatorRpcEndpoint(msg.sender, rpcEndpoint);
    }

    // ================ OPERATOR VIEW METHODS =================== //

    /**
     * @notice Gets the operator stake for the vault.
     * @param operator The address of the operator.
     * @param collateral The address of the collateral.
     * @return The operator stake.
     */
    function getOperatorStake(address operator, address collateral) public view returns (uint256) {
        // TODO(V2): only do this for active operators & vaults?
        return getOperatorStakeAt(operator, collateral, _now());
    }

    /**
     * @notice Gets the operator stake for the vault at a specific timestamp.
     * @param operator The address of the operator.
     * @param collateral The address of the collateral.
     * @param timestamp The timestamp to get the stake at.
     * @return The operator stake.
     */
    function getOperatorStakeAt(address operator, address collateral, uint48 timestamp) public view returns (uint256) {
        // TODO(V2): check if vault and operator are registered, associated & active
        // Distinguish between shared vaults and operator vaults

        // Get vault for collateral
        address vault;
        for (uint256 i = 0; i < _vaultWhitelist.length(); i++) {
            (address _vault,,) = _vaultWhitelist.at(i);
            if (IVaultStorage(_vault).collateral() == collateral) {
                vault = _vault;
                break;
            }
        }

        if (vault == address(0)) {
            revert UnauthorizedVault();
        }

        bytes32 networkId = NETWORK.subnetwork(DEFAULT_SUBNETWORK);
        return IBaseDelegator(IVault(vault).delegator()).stakeAt(networkId, operator, timestamp, "");
    }

    function getOperatorCollaterals(
        address operator
    ) public view returns (address[] memory, uint256[] memory) {
        address[] memory tokens = new address[](_vaultWhitelist.length());
        uint256[] memory amounts = new uint256[](_vaultWhitelist.length());

        bytes32 networkId = NETWORK.subnetwork(DEFAULT_SUBNETWORK);
        // TODO:!!!!
        uint48 epochStartTs = 0;

        for (uint256 i = 0; i < _vaultWhitelist.length(); i++) {
            // TODO(V2): only get active vaults
            (address vault, uint48 enabledTime, uint48 disabledTime) = _vaultWhitelist.at(i);

            if (!_wasEnabledAt(enabledTime, disabledTime, epochStartTs)) {
                // Set the token, keep the amount at 0
                tokens[i] = IVaultStorage(vault).collateral();
                continue;
            }

            tokens[i] = IVaultStorage(vault).collateral();
            amounts[i] = IBaseDelegator(IVault(vault).delegator()).stake(networkId, operator);
        }

        return (tokens, amounts);
    }

    // ================ VAULTS ===================== //

    /**
     * @notice Whitelists a vault for the network.
     * @param vault The address of the vault
     */
    function whitelistVault(
        address vault
    ) public onlyOwner {
        // Validate the vault
        _validateVault(vault);

        // Registers and enables the vault
        _vaultWhitelist.register(_now(), vault);

        emit VaultWhitelisted(vault);
    }

    /**
     * @notice Removes a whitelisted vault from the network.
     * @param vault The address of the vault
     */
    function removeVault(
        address vault
    ) public onlyOwner {
        _vaultWhitelist.unregister(_now(), SLASHING_WINDOW, vault);
        emit VaultRemoved(vault);
    }

    /**
     * @notice Pause a vault across the network (whitelist, operator-specific, and shared).
     * @param vault The address of the vault
     */
    function pauseVault(
        address vault
    ) public onlyOwner {
        _vaultWhitelist.pause(_now(), vault);
        emit VaultPaused(vault);
    }

    /**
     * @notice Unpause a vault
     * @param vault The address of the vault
     */
    function unpauseVault(
        address vault
    ) public onlyOwner {
        _vaultWhitelist.unpause(_now(), SLASHING_WINDOW, vault);
        emit VaultUnpaused(vault);
    }

    /**
     * @notice Returns the total number of whitelisted vaults.
     */
    function vaultWhitelistLength() public view returns (uint256) {
        return _vaultWhitelist.length();
    }

    /**
     * @notice Validates if a vault is properly initialized and registered
     * @param vault The vault address to validate
     * @dev Adapted from https://github.com/symbioticfi/middleware-sdk/blob/68334572da818cc547aca8e729321e98df97a2a8/src/managers/VaultManager.sol
     */
    function _validateVault(
        address vault
    ) private view {
        if (!IRegistry(VAULT_REGISTRY).isEntity(vault)) {
            revert NotVault();
        }

        if (!IVault(vault).isInitialized()) {
            revert VaultNotInitialized();
        }

        if (_vaultWhitelist.contains(vault)) {
            revert VaultAlreadyRegistered();
        }

        // TODO(V3): slasher checks:

        // uint48 vaultEpoch = IVault(vault).epochDuration();
        // address slasher = IVault(vault).slasher();
        // if (slasher != address(0)) {
        //     uint64 slasherType = IEntity(slasher).TYPE();
        //     if (slasherType == uint64(SlasherType.VETO)) {
        //         vaultEpoch -= IVetoSlasher(slasher).vetoDuration();
        //     } else if (slasherType > uint64(SlasherType.VETO)) {
        //         revert UnknownSlasherType();
        //     }
        // }

        // if (vaultEpoch < SLASHING_WINDOW) {
        //     revert VaultEpochTooShort();
        // }
    }

    /**
     * @notice Validates if a vault has an operator-specific delegator type (OPERATOR_SPECIFIC or OPERATOR_NETWORK_SPECIFIC)
     * @param operator The operator address
     * @param vault The vault address
     */
    function _validateOperatorVault(address operator, address vault) internal view {
        address delegator = IVault(vault).delegator();
        uint64 delegatorType = IEntity(delegator).TYPE();
        if (
            (
                delegatorType != uint64(DelegatorType.OPERATOR_SPECIFIC)
                    && delegatorType != uint64(DelegatorType.OPERATOR_NETWORK_SPECIFIC)
            ) || IOperatorSpecificDelegator(delegator).operator() != operator
        ) {
            revert NotOperatorSpecificVault();
        }
    }

    // ========= HELPER FUNCTIONS =========

    /// @notice Check if a map entry was active at a given timestamp.
    /// @param enabledTime The enabled time of the map entry.
    /// @param disabledTime The disabled time of the map entry.
    /// @param timestamp The timestamp to check the map entry status at.
    /// @return True if the map entry was active at the given timestamp, false otherwise.
    function _wasEnabledAt(uint48 enabledTime, uint48 disabledTime, uint48 timestamp) private pure returns (bool) {
        return enabledTime != 0 && enabledTime <= timestamp && (disabledTime == 0 || disabledTime >= timestamp);
    }

    /**
     * @notice Returns the current timestamp
     * @return timestamp The current timestamp
     */
    function _now() internal view returns (uint48) {
        return Time.timestamp();
    }
}
