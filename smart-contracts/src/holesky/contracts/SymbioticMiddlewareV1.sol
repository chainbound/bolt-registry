// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {Operators} from "@symbiotic/middleware-sdk/extensions/operators/Operators.sol";
import {SharedVaults} from "@symbiotic/middleware-sdk/extensions/SharedVaults.sol";
import {KeyManagerAddress} from "@symbiotic/middleware-sdk/extensions/managers/keys/KeyManagerAddress.sol";
import {EqualStakePower} from "@symbiotic/middleware-sdk/extensions/managers/stake-powers/EqualStakePower.sol";
import {EpochCapture} from "@symbiotic/middleware-sdk/extensions/managers/capture-timestamps/EpochCapture.sol";
import {ECDSASig} from "@symbiotic/middleware-sdk/extensions/managers/sigs/ECDSASig.sol";
import {OwnableAccessManager} from "@symbiotic/middleware-sdk/extensions/managers/access/OwnableAccessManager.sol";

import {Subnetwork} from "@symbiotic/core/contracts/libraries/Subnetwork.sol";
import {INetworkRegistry} from "@symbiotic/core/interfaces/INetworkRegistry.sol";

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
contract SymbioticMiddlewareV1 is
    Operators,
    KeyManagerAddress,
    ECDSASig,
    EqualStakePower,
    EpochCapture,
    OwnableAccessManager,
    UUPSUpgradeable
{
    using Subnetwork for address;

    /**
     * @notice The address of the bolt operators registry.
     */
    address public BOLT_REGISTRY;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     * This can be validated with the Openzeppelin Foundry Upgrades toolkit.
     *
     * Total storage slots: 50
     */
    uint256[49] private __gap;

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
     * @param networkRegistry The address of the network registry
     * @param slashingWindow The duration of the slashing window (unused in V1)
     * @param vaultRegistry The address of the vault registry
     * @param operatorRegistry The address of the operator registry
     * @param operatorNetOptin The address of the operator network opt-in service
     * @param reader The address of the reader contract used for delegatecall
     * @dev We put all of the contract dependencies in the constructor to make it easier to (re-)deploy
     *      when dependencies are upgraded.
     */
    function initialize(
        address owner,
        address boltRegistry,
        address networkRegistry,
        uint48 epochDuration,
        uint48 slashingWindow,
        address vaultRegistry,
        address operatorRegistry,
        address operatorNetOptin,
        address reader
    ) public initializer {
        // Register the network
        // IMPORTANT NOTE: Don't do this in any upgraded initializers or the initializer
        // will revert!
        INetworkRegistry(networkRegistry).registerNetwork();

        // Initialize middleware
        __BaseMiddleware_init(address(this), slashingWindow, vaultRegistry, operatorRegistry, operatorNetOptin, reader);

        // Initialize owner access
        __OwnableAccessManager_init(owner);

        // Initialize the epoch capture
        __EpochCapture_init(epochDuration);

        BOLT_REGISTRY = boltRegistry;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override checkAccess {}

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
    //     -
}
