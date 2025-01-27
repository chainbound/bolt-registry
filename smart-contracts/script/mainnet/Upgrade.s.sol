// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script, console} from "forge-std/Script.sol";

import {ERC1967Proxy} from "@openzeppelin-v5.0.0/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Upgrades, Options} from "@openzeppelin/foundry-upgrades/src/Upgrades.sol";

import {IRegistry} from "@symbiotic/core/interfaces/common/IRegistry.sol";
import {IOptInService} from "@symbiotic/core/interfaces/service/IOptInService.sol";

import {IAllocationManager} from "@eigenlayer/src/contracts/interfaces/IAllocationManager.sol";
import {IDelegationManager} from "@eigenlayer/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "@eigenlayer/src/contracts/interfaces/IStrategyManager.sol";
import {IAVSDirectory} from "@eigenlayer/src/contracts/interfaces/IAVSDirectory.sol";

import {SymbioticMiddlewareV1} from "../../src/contracts/SymbioticMiddlewareV1.sol";
import {EigenLayerMiddlewareV1} from "../../src/contracts/EigenLayerMiddlewareV1.sol";
import {EigenLayerMiddlewareV2} from "../../src/contracts/EigenLayerMiddlewareV2.sol";
import {OperatorsRegistryV1} from "../../src/contracts/OperatorsRegistryV1.sol";
import {IOperatorsRegistryV1} from "../../src/interfaces/IOperatorsRegistryV1.sol";

/// @notice Upgrades any of the OperatorsRegistry, SymbioticMiddleware or EigenLayerMiddleware contracts.
/// @dev Before running this script, make sure to update the variables in the script correctly.
/// @dev Use with one of the following commands:
///
/// 1. Upgrade symbiotic middleware:
///    forge script script/mainnet/Upgrade.s.sol --rpc-url https://eth.drpc.org --private-key $PRIVATE_KEY --broadcast -vvvv --sig "upgradeSymbioticMiddleware()"
///
/// 2. Upgrade eigenlayer middleware:
///    forge script script/mainnet/Upgrade.s.sol --rpc-url https://eth.drpc.org --private-key $PRIVATE_KEY --broadcast -vvvv --sig "upgradeEigenLayerMiddleware()"
///
/// 3. Upgrade operators registry:
///    forge script script/mainnet/Upgrade.s.sol --rpc-url https://eth.drpc.org --private-key $PRIVATE_KEY --broadcast -vvvv --sig "upgradeOperatorsRegistry()"
contract UpgradeRegistry is Script {
    function upgradeSymbioticMiddleware() public {
        address admin = msg.sender;

        console.log("Upgrading Symbiotic middleware with admin: %s", admin);
        console.log("Did you update the variables in this script correctly?");

        // Note: these variables MUST be updated correctly before each run of this script
        string memory UPGRADE_FROM = "SymbioticMiddlewareV1";
        address OLD_IMPLEMENTATION = 0x0aC0488aF24E9064F703a2263762Db26EdFc5Bbe;
        string memory UPGRADE_TO = "SymbioticMiddlewareV2";

        console.log("Upgrading Symbiotic middleware from %s to %s", UPGRADE_FROM, UPGRADE_TO);

        // TODO: make sure the admin is also the owner of the old middleware

        Options memory opts;
        opts.unsafeSkipAllChecks = true;
        opts.referenceContract = UPGRADE_FROM;

        // bytes memory initBytes = abi.encodeCall(
        //     SymbioticMiddlewareV2.initializeV2,
        //     (
        //         admin,
        //         // TODO: add params here
        //     )
        // );

        // vm.startBroadcast(admin);

        // Upgrades.upgradeProxy(OLD_IMPLEMENTATION, UPGRADE_TO, initBytes, opts);

        // vm.stopBroadcast();

        console.log("Symbiotic middleware upgraded successfully");
    }

    function upgradeEigenLayerMiddleware() public {
        address admin = msg.sender;

        console.log("Upgrading EigenLayer middleware with admin: %s", admin);
        console.log("Did you update the variables in this script correctly?");

        // Note: these variables MUST be updated correctly before each run of this script
        string memory UPGRADE_FROM = "EigenLayerMiddlewareV1";
        address OLD_IMPLEMENTATION = 0xF66Ae0a151E4Dc7c4b7cCd2d0D2cc662F1F3a103;
        string memory UPGRADE_TO = "EigenLayerMiddlewareV2";

        console.log("Upgrading EigenLayer middleware from %s to %s", UPGRADE_FROM, UPGRADE_TO);

        // TODO: make sure the admin is also the owner of the old middleware

        Options memory opts;
        opts.unsafeSkipAllChecks = true;
        opts.referenceContract = UPGRADE_FROM;

        // Initializer params, these should be double checked on each upgrade!
        IOperatorsRegistryV1 _operatorsRegistry = IOperatorsRegistryV1(0x630869F51C012C797FEb3D9006F4280587C78b3f);
        IAVSDirectory _avsDirectory = IAVSDirectory(0x135DDa560e946695d6f155dACaFC6f1F25C1F5AF);
        IAllocationManager _eigenlayerAllocationManager = IAllocationManager(0x0000000000000000000000000000000000000000);
        IDelegationManager _eigenlayerDelegationManager = IDelegationManager(0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A);
        IStrategyManager _eigenlayerStrategyManager = IStrategyManager(0x858646372CC42E1A627fcE94aa7A7033e7CF075A);

        bytes memory initBytes = abi.encodeCall(
            EigenLayerMiddlewareV2.initializeV2,
            (
                admin, // address owner
                _operatorsRegistry,
                _avsDirectory,
                _eigenlayerAllocationManager,
                _eigenlayerDelegationManager,
                _eigenlayerStrategyManager
            )
        );

        vm.startBroadcast(admin);

        Upgrades.upgradeProxy(OLD_IMPLEMENTATION, UPGRADE_TO, initBytes, opts);

        vm.stopBroadcast();

        console.log("EigenLayer middleware upgraded successfully");
    }

    function upgradeOperatorsRegistry() public {
        address admin = msg.sender;

        console.log("Upgrading OperatorsRegistry with admin: %s", admin);
        console.log("Did you update the variables in this script correctly?");

        // Note: these variables MUST be updated correctly before each run of this script
        string memory UPGRADE_FROM = "OperatorsRegistryV1";
        address OLD_IMPLEMENTATION = 0x0F2a3B9Caea77eA58BFb42ea81c4292157122D63;
        string memory UPGRADE_TO = "OperatorsRegistryV2";

        console.log("Upgrading OperatorsRegistry from %s to %s", UPGRADE_FROM, UPGRADE_TO);

        Options memory opts;
        opts.unsafeSkipAllChecks = true;
        opts.referenceContract = UPGRADE_FROM;

        // bytes memory initBytes = abi.encodeCall(
        //     OperatorsRegistryV2.initializeV2,
        //     (
        //         admin,
        //         // TODO: add params here
        //     )
        // );

        // vm.startBroadcast(admin);

        // Upgrades.upgradeProxy(OLD_IMPLEMENTATION, UPGRADE_TO, initBytes, opts);

        // vm.stopBroadcast();

        console.log("OperatorsRegistry upgraded successfully");
    }
}
