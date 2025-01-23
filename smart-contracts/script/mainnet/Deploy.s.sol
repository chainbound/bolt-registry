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

import {BoltSymbioticMiddlewareV1} from "../../src/holesky/contracts/BoltSymbioticMiddlewareV1.sol";
import {BoltEigenLayerMiddlewareV1} from "../../src/holesky/contracts/BoltEigenLayerMiddlewareV1.sol";
import {OperatorsRegistryV1} from "../../src/holesky/contracts/OperatorsRegistryV1.sol";
import {IBoltRestakingMiddlewareV1} from "../../src/holesky/interfaces/IBoltRestakingMiddlewareV1.sol";

/// @notice Deploys the OperatorsRegistryV1, BoltSymbioticMiddlewareV1 and BoltEigenLayerMiddlewareV1 contracts,
/// and links them by setting the restaking middlewares in the registry.
contract DeployRegistry is Script {
    uint48 EPOCH_DURATION = 1 days;

    // This is the address of the Safe multisig that controls the network
    // and will be the admin too.
    address ADMIN = 0xA42ec46F2c9DC671a72218E145CC13dc119fB722;

    OperatorsRegistryV1 registry;
    // BoltSymbioticMiddlewareV1 symbioticMiddleware;
    // BoltEigenLayerMiddlewareV1 eigenLayerMiddleware;

    string registryName = "OperatorsRegistryV1";
    string symbioticMiddlewareName = "BoltSymbioticMiddlewareV1";
    string eigenLayerMiddlewareName = "BoltEigenLayerMiddlewareV1";

    // =============== Symbiotic Holesky Deployments ================== //
    IRegistry vaultRegistry = IRegistry(0x407A039D94948484D356eFB765b3c74382A050B4);
    IRegistry operatorRegistry = IRegistry(0x6F75a4ffF97326A00e52662d82EA4FdE86a2C548);
    IOptInService operatorNetOptin = IOptInService(0x58973d16FFA900D11fC22e5e2B6840d9f7e13401);

    // =============== EigenLayer Holesky Deployments ================== //
    IDelegationManager holeskyDelegationManager = IDelegationManager(0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A);
    IStrategyManager holeskyStrategyManager = IStrategyManager(0x858646372CC42E1A627fcE94aa7A7033e7CF075A);
    IAVSDirectory holeskyAVSDirectory = IAVSDirectory(0x135DDa560e946695d6f155dACaFC6f1F25C1F5AF);

    function run() public {
        vm.startBroadcast();

        // TODO: Fix safe deploy, currently failing with `ASTDereferencerError` from openzeppelin
        Options memory opts;
        opts.unsafeSkipAllChecks = true;

        bytes memory initParams = abi.encodeCall(OperatorsRegistryV1.initialize, (ADMIN, EPOCH_DURATION));

        // address middleware = Upgrades.deployUUPSProxy("SymbioticMiddlewareV1", initParams, opts);
        address operatorsRegistry = Upgrades.deployUUPSProxy(registryName, initParams, opts);
        console.log("Deployed %s at %s", registryName, operatorsRegistry);

        registry = OperatorsRegistryV1(operatorsRegistry);

        initParams = abi.encodeCall(
            BoltSymbioticMiddlewareV1.initialize,
            (ADMIN, ADMIN, registry, vaultRegistry, operatorRegistry, operatorNetOptin)
        );

        address symbioticMiddleware = Upgrades.deployUUPSProxy(symbioticMiddlewareName, initParams, opts);
        console.log("Deployed %s at %s", symbioticMiddlewareName, symbioticMiddleware);

        initParams = abi.encodeCall(
            BoltEigenLayerMiddlewareV1.initialize,
            (
                ADMIN,
                registry,
                holeskyAVSDirectory,
                // Doesn't exist yet on mainnet
                IAllocationManager(address(0)),
                holeskyDelegationManager,
                holeskyStrategyManager
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

    function postDeployEigenLayer(
        BoltEigenLayerMiddlewareV1 middleware
    ) public {
        // 1. Whitelist strategies

        // 2. Initialize AVS with AVS directory
        middleware.updateAVSMetadataURI("TODO", "TODO");
    }

    function postDeploySymbiotic(
        BoltSymbioticMiddlewareV1 middleware
    ) public {
        // 1. Whitelist vaults
        // No vaults yet. This will need to be done by the admin.
    }
}
