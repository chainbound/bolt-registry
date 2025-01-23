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
    IAllocationManager holeskyAllocationManager = IAllocationManager(0x78469728304326CBc65f8f95FA756B0B73164462);
    IDelegationManager holeskyDelegationManager = IDelegationManager(0xA44151489861Fe9e3055d95adC98FbD462B948e7);
    IStrategyManager holeskyStrategyManager = IStrategyManager(0xdfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6);
    IAVSDirectory holeskyAVSDirectory = IAVSDirectory(0x055733000064333CaDDbC92763c58BF0192fFeBf);

    function run() public {
        // Admin == network
        address admin = msg.sender;
        address network = admin;

        vm.startBroadcast(admin);

        // TODO: Fix safe deploy, currently failing with `ASTDereferencerError` from openzeppelin
        Options memory opts;
        opts.unsafeSkipAllChecks = true;

        bytes memory initParams = abi.encodeCall(OperatorsRegistryV1.initialize, (admin, EPOCH_DURATION));

        // address middleware = Upgrades.deployUUPSProxy("SymbioticMiddlewareV1", initParams, opts);
        address operatorsRegistry = Upgrades.deployUUPSProxy(registryName, initParams, opts);
        console.log("Deployed %s at %s", registryName, operatorsRegistry);

        registry = OperatorsRegistryV1(operatorsRegistry);

        initParams = abi.encodeCall(
            BoltSymbioticMiddlewareV1.initialize,
            (admin, network, registry, vaultRegistry, operatorRegistry, operatorNetOptin)
        );

        address symbioticMiddleware = Upgrades.deployUUPSProxy(symbioticMiddlewareName, initParams, opts);
        console.log("Deployed %s at %s", symbioticMiddlewareName, symbioticMiddleware);

        registry.updateRestakingMiddleware("SYMBIOTIC", IBoltRestakingMiddlewareV1(symbioticMiddleware));

        initParams = abi.encodeCall(
            BoltEigenLayerMiddlewareV1.initialize,
            (
                admin,
                registry,
                holeskyAVSDirectory,
                holeskyAllocationManager,
                holeskyDelegationManager,
                holeskyStrategyManager
            )
        );

        address eigenLayerMiddleware = Upgrades.deployUUPSProxy(eigenLayerMiddlewareName, initParams, opts);
        console.log("Deployed %s at %s", eigenLayerMiddlewareName, eigenLayerMiddleware);

        registry.updateRestakingMiddleware("EIGENLAYER", IBoltRestakingMiddlewareV1(eigenLayerMiddleware));

        vm.stopBroadcast();
    }
}
