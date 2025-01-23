// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script, console} from "forge-std/Script.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Upgrades, Options} from "@openzeppelin/foundry-upgrades/src/Upgrades.sol";

import {IRegistry} from "@symbiotic/core/interfaces/common/IRegistry.sol";
import {IOptInService} from "@symbiotic/core/interfaces/service/IOptInService.sol";

import {IAllocationManager} from "@eigenlayer/src/contracts/interfaces/IAllocationManager.sol";
import {IDelegationManager} from "@eigenlayer/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "@eigenlayer/src/contracts/interfaces/IStrategyManager.sol";
import {IAVSDirectory} from "@eigenlayer/src/contracts/interfaces/IAVSDirectory.sol";

import {SymbioticMiddlewareV1} from "../../src/contracts/SymbioticMiddlewareV1.sol";
import {EigenLayerMiddlewareV1} from "../../src/contracts/EigenLayerMiddlewareV1.sol";
import {OperatorsRegistryV1} from "../../src/contracts/OperatorsRegistryV1.sol";

/// @notice Deploys the OperatorsRegistryV1, SymbioticMiddlewareV1 and EigenLayerMiddlewareV1 contracts,
/// and links them by setting the restaking middlewares in the registry.
contract DeployRegistry is Script {
    uint48 EPOCH_DURATION = 1 days;

    // This is the address of the Safe multisig that controls the network
    // and will be the admin too.
    address ADMIN = 0xA42ec46F2c9DC671a72218E145CC13dc119fB722;

    OperatorsRegistryV1 registry;

    string registryName = "OperatorsRegistryV1";
    string symbioticMiddlewareName = "SymbioticMiddlewareV1";
    string eigenLayerMiddlewareName = "EigenLayerMiddlewareV1";

    // =============== Symbiotic Mainnet Deployments ================== //
    IRegistry vaultRegistry = IRegistry(0xAEb6bdd95c502390db8f52c8909F703E9Af6a346);
    IRegistry operatorRegistry = IRegistry(0xAd817a6Bc954F678451A71363f04150FDD81Af9F);
    IOptInService operatorNetOptin = IOptInService(0x7133415b33B438843D581013f98A08704316633c);

    // =============== EigenLayer Mainnet Deployments ================== //
    IDelegationManager delegationManager = IDelegationManager(0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A);
    IStrategyManager stategyManager = IStrategyManager(0x858646372CC42E1A627fcE94aa7A7033e7CF075A);
    IAVSDirectory avsDirectory = IAVSDirectory(0x135DDa560e946695d6f155dACaFC6f1F25C1F5AF);

    function run() public {
        vm.startBroadcast();

        Options memory opts;
        opts.unsafeSkipAllChecks = true;

        bytes memory initParams = abi.encodeCall(OperatorsRegistryV1.initialize, (ADMIN, EPOCH_DURATION));

        // address middleware = Upgrades.deployUUPSProxy("SymbioticMiddlewareV1", initParams, opts);
        address operatorsRegistry = Upgrades.deployUUPSProxy(registryName, initParams, opts);
        console.log("Deployed %s at %s", registryName, operatorsRegistry);

        registry = OperatorsRegistryV1(operatorsRegistry);

        initParams = abi.encodeCall(
            SymbioticMiddlewareV1.initialize,
            (ADMIN, ADMIN, registry, vaultRegistry, operatorRegistry, operatorNetOptin)
        );

        address symbioticMiddleware = Upgrades.deployUUPSProxy(symbioticMiddlewareName, initParams, opts);
        console.log("Deployed %s at %s", symbioticMiddlewareName, symbioticMiddleware);

        initParams = abi.encodeCall(
            EigenLayerMiddlewareV1.initialize,
            (
                ADMIN,
                registry,
                avsDirectory,
                // Doesn't exist yet on mainnet
                IAllocationManager(address(0)),
                delegationManager,
                stategyManager
            )
        );

        address eigenLayerMiddleware = Upgrades.deployUUPSProxy(eigenLayerMiddlewareName, initParams, opts);
        console.log("Deployed %s at %s", eigenLayerMiddlewareName, eigenLayerMiddleware);

        // ================ EigenLayer Post-Deploy Steps ================ //
        // These steps need to be undertaken with the ADMIN Safe.
        //
        // 1. updateRestakingMiddleware on OperatorsRegistry with EIGENLAYER
        // 2. Initialize AVS with AVS directory: updateAVSMetadataURI
        // 3. Whitelist strategies

        // ================ Symbiotic Post-Deploy Steps ================ //
        // These steps need to be undertaken with the ADMIN Safe.
        //
        // 1. updateRestakingMiddleware on OperatorsRegistry with SYMBIOTIC
        // 2. Whitelist vaults

        vm.stopBroadcast();
    }
}
