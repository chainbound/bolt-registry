// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

import {IVault} from "@symbiotic/core/interfaces/vault/IVault.sol";
import {IEntity} from "@symbiotic/core/interfaces/common/IEntity.sol";
import {IOperatorSpecificDelegator} from "@symbiotic/core/interfaces/delegator/IOperatorSpecificDelegator.sol";
import {IBaseDelegator} from "@symbiotic/core/interfaces/delegator/IBaseDelegator.sol";
import {IRegistry} from "@symbiotic/core/interfaces/common/IRegistry.sol";
import {IOptInService} from "@symbiotic/core/interfaces/service/IOptInService.sol";
import {Subnetwork} from "@symbiotic/core/contracts/libraries/Subnetwork.sol";
import {INetworkRegistry} from "@symbiotic/core/interfaces/INetworkRegistry.sol";
import {INetworkMiddlewareService} from "@symbiotic/core/interfaces/service/INetworkMiddlewareService.sol";

import {PauseableEnumerableSet} from "@symbiotic/middleware-sdk/libraries/PauseableEnumerableSet.sol";

/**
 * @title SymbioticMiddlewareV1
 * @author Chainbound Developers <dev@chainbound.io>
 * @notice This contract is responsible for interacting with the Symbiotic restaking protocol contracts. It is both
 *         the middleware and the actual network contract, because it self-registers with the network registry.
 * @dev This contract implements the following middleware-sdk extensions:
 *      - Operators: Provides operator management (keys, vaults, registration)
 *      - KeyManagerAddress: Manages storage and validation of operator keys using address values
 *      - ECDSASig: Verify ECDSA keys against operator addresses
 *      - EqualStakePower: Equal stake to power for all registered vaults
 *      - TimestampCapture: Capture and store block timestamps
 *      - OwnableAccessManager: Provides onlyOwner access control
 *
 * For more information on extensions, see <https://docs.symbiotic.fi/middleware-sdk/extensions>.
 * All public view functions are implemented in the `BaseMiddlewareReader`: <https://docs.symbiotic.fi/middleware-sdk/api-reference/middleware/BaseMiddlewareReader>
 */
contract SymbioticMiddlewareV1 is OwnableUpgradeable, UUPSUpgradeable {
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
    address public BOLT_REGISTRY;

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

    /**
     * @notice The set of whitelisted vaults for the network.
     */
    PauseableEnumerableSet.AddressSet private _vaultWhitelist;

    /**
     * @notice The set of vaults for each operator.
     */
    mapping(address => PauseableEnumerableSet.AddressSet) _operatorVaults;

    /**
     * @notice Vaults to operators mapping.
     */
    EnumerableMap.AddressToAddressMap _vaultOperator;

    PauseableEnumerableSet.AddressSet private _operators;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shift_initializeNetworkage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     * This can be validated with the Openzeppelin Foundry Upgrades toolkit.
     *
     * Total storage slots: 50
     */
    uint256[49] private __gap;

    enum DelegatorType {
        FULL_RESTAKE,
        NETWORK_RESTAKE,
        OPERATOR_SPECIFIC,
        OPERATOR_NETWORK_SPECIFIC
    }

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
     * @notice Modifier to restrict access to the bolt registry.
     * @dev This modifier exists alongside `checkAccess`, which restricts access to the owner.
     */
    modifier onlyBolt() {
        require(msg.sender == BOLT_REGISTRY, "SymbioticMiddlewareV1: Only the bolt registry can call this function");
        _;
    }

    /**
     * @notice Constructor for initializing the SymbioticMiddlewareV1 contract
     * @param owner The address of the owner
     * @param networkMiddlewareService The address of the network middleware service
     * @param slashingWindow The duration of the slashing window (unused in V1)
     * @param vaultRegistry The address of the vault registry
     * @param operatorRegistry The address of the operator registry
     * @param operatorNetOptin The address of the operator network opt-in service
     * @dev We put all of the contract dependencies in the constructor to make it easier to (re-)deploy
     *      when dependencies are upgraded.
     */
    function initialize(
        address owner,
        address boltRegistry,
        address networkMiddlewareService,
        uint48 epochDuration,
        uint48 slashingWindow,
        address vaultRegistry,
        address operatorRegistry,
        address operatorNetOptin
    ) public initializer {
        __Ownable_init(owner);

        // Initialize the network with Symbiotic
        _initializeNetwork(networkMiddlewareService);

        BOLT_REGISTRY = boltRegistry;
        SLASHING_WINDOW = slashingWindow;
        EPOCH_DURATION = epochDuration;
        VAULT_REGISTRY = vaultRegistry;
        OPERATOR_REGISTRY = operatorRegistry;
        OPERATOR_NET_OPTIN = operatorNetOptin;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    /**
     * @notice Initialize the network with the network middleware service.
     * @param networkMiddlewareService The address of the network middleware service.
     * @dev IMPORTANT: This MUST only be called once, in the first initializer.
     */
    function _initializeNetwork(
        address networkMiddlewareService
    ) public onlyOwner {
        address networkRegistry = INetworkMiddlewareService(networkMiddlewareService).NETWORK_REGISTRY();

        INetworkRegistry(networkRegistry).registerNetwork();

        // Set the middleware
        INetworkMiddlewareService(networkMiddlewareService).setMiddleware(address(this));

        NETWORK = address(this);
        START_TIMESTAMP = _now();
    }

    // TODO:
    // - Key management
    // - Network management (this contract is the network)
    // - Operator
    //     - Operator registration
    //     - Operator deregistration
    //     - Operator pausing / unpausing
    // - Vaults
    //     - Shared vault registration / deregistration
    //     - Vault pausing / unpausing
    //     - Vault collateral tracking
    //     - Vault whitelisting

    // ================ OPERATORS ===================== //
    //
    // These functions are only callable by the bolt registry.
    // All external operator management is done through the bolt registry.

    /**
     * @notice Register an operator in the registry
     * @param operator The address of the operator
     * @param vault The address of the vault
     */
    function registerOperator(address operator, address vault) public onlyBolt {
        if (!IRegistry(OPERATOR_REGISTRY).isEntity(operator)) {
            revert NotOperator();
        }

        if (!IOptInService(OPERATOR_NET_OPTIN).isOptedIn(operator, NETWORK)) {
            revert OperatorNotOptedIn();
        }

        _operators.register(_now(), operator);
        _validateOperatorVault(operator, vault);
    }

    /**
     * @notice Register an operator -> vault association.
     * @param operator The address of the operator
     * @param vault The address of the vault
     */
    function registerOperatorVault(address operator, address vault) public onlyBolt {
        if (!_operators.contains(operator)) {
            revert OperatorNotRegistered();
        }

        // Only allow registration of whitelisted vaults
        if (!_vaultWhitelist.contains(vault)) {
            revert UnauthorizedVault();
        }

        // Validate vault type
        _validateOperatorVault(operator, vault);

        _operatorVaults[operator].register(_now(), vault);
        _vaultOperator.set(vault, operator);
    }

    /**
     * @notice Deregister an operator from the registry
     * @param operator The address of the operator
     */
    function deregisterOperator(
        address operator
    ) public onlyBolt {
        _operators.unregister(_now(), SLASHING_WINDOW, operator);

        // QUESTION: in the future we may not want to remove the vaults immediately, in case
        // of a pending penalty that the operator is trying to avoid.
        PauseableEnumerableSet.AddressSet storage vaults = _operatorVaults[operator];
        delete _operatorVaults[operator];

        for (uint256 i = 0; i < vaults.length(); i++) {
            (address vault,,) = vaults.at(i);
            _vaultOperator.remove(vault);
        }
    }

    /**
     * @notice Deregister an operator vault from the registry
     * @param operator The address of the operator
     * @param vault The address of the vault
     */
    function deregisterOperatorVault(address operator, address vault) public onlyBolt {
        _operatorVaults[operator].unregister(_now(), SLASHING_WINDOW, vault);
        _vaultOperator.remove(vault);
    }

    /**
     * @notice Pause an operator
     * @param operator The address of the operator
     */
    function pauseOperator(
        address operator
    ) public onlyOwner {
        _operators.pause(_now(), operator);
    }

    /**
     * @notice Unpause an operator
     * @param operator The address of the operator
     */
    function unpauseOperator(
        address operator
    ) public onlyOwner {
        _operators.unpause(_now(), SLASHING_WINDOW, operator);
    }

    /**
     * @notice Returns the total number of registered operators
     */
    function operatorsLength() public view returns (uint256) {
        return _operators.length();
    }

    // ================ VAULTS ===================== //

    /**
     * @notice Whitelists a vault for the network.
     * @param vault The address of the vault
     */
    function whitelistVault(address vault, uint256 networkLimit) public onlyOwner {
        // Validate the vault
        _validateVault(vault);

        // Registers and enables the vault
        _vaultWhitelist.register(_now(), vault);

        // Set the max network limit for the vault
        IBaseDelegator(IVault(vault).delegator()).setMaxNetworkLimit(DEFAULT_SUBNETWORK, networkLimit);
    }

    /**
     * @notice Removes a whitelisted vault from the network.
     * @param vault The address of the vault
     */
    function removeVault(
        address vault
    ) public onlyOwner {
        _vaultWhitelist.unregister(_now(), SLASHING_WINDOW, vault);
        _vaultOperator.remove(vault);

        // Set the max network limit for the vault to 0
        IBaseDelegator(IVault(vault).delegator()).setMaxNetworkLimit(DEFAULT_SUBNETWORK, 0);
    }

    /**
     * @notice Pause a vault
     * @param vault The address of the vault
     */
    function pauseVault(
        address vault
    ) public onlyOwner {
        _vaultWhitelist.pause(_now(), vault);
        address operator = _vaultOperator.get(vault);
        if (operator != address(0)) {
            _operatorVaults[operator].pause(_now(), vault);
        }
    }

    /**
     * @notice Unpause a vault
     * @param vault The address of the vault
     */
    function unpauseVault(
        address vault
    ) public onlyOwner {
        _vaultWhitelist.unpause(_now(), SLASHING_WINDOW, vault);
        address operator = _vaultOperator.get(vault);
        if (operator != address(0)) {
            _operatorVaults[operator].unpause(_now(), SLASHING_WINDOW, vault);
        }
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

        // TODO: slasher checks:

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
     * @notice Validates if a vault has an operator-specific delegator type
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

    /**
     * @notice Returns the current timestamp minus 1 second.
     * @return timestamp The current timestamp minus 1 second.
     */
    function getCaptureTimestamp() public view returns (uint48 timestamp) {
        return _now() - 1;
    }

    /**
     * @notice Returns the current timestamp
     * @return timestamp The current timestamp
     */
    function _now() internal view returns (uint48) {
        return Time.timestamp();
    }
}
