// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {
    IAllocationManager, IAllocationManagerTypes
} from "@eigenlayer/src/contracts/interfaces/IAllocationManager.sol";
import {IDelegationManager} from "@eigenlayer/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "@eigenlayer/src/contracts/interfaces/IStrategyManager.sol";

import {OperatorsRegistryV1} from "../../src/holesky/contracts/OperatorsRegistryV1.sol";
import {BoltEigenLayerMiddlewareV1} from "../../src/holesky/contracts/BoltEigenLayerMiddlewareV1.sol";

contract BoltEigenLayerMiddlewareV1Test is Test {
    OperatorsRegistryV1 registry;
    BoltEigenLayerMiddlewareV1 middleware;

    address admin;

    address holeskyAllocationManager = 0x78469728304326CBc65f8f95FA756B0B73164462;
    address holeskyDelegationManager = 0xA44151489861Fe9e3055d95adC98FbD462B948e7;
    address holeskyStrategyManager = 0xdfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6;

    function setUp() public {
        vm.createSelectFork("https://geth-holesky.bolt.chainbound.io");

        admin = makeAddr("admin");
        vm.deal(admin, 1000 ether);

        vm.startPrank(admin);
        registry = new OperatorsRegistryV1();
        registry.initialize(admin);

        middleware = new BoltEigenLayerMiddlewareV1();
        middleware.initialize(
            admin,
            IAllocationManager(holeskyAllocationManager),
            IDelegationManager(holeskyDelegationManager),
            IStrategyManager(holeskyStrategyManager)
        );

        // Add the middleware to the registry
        registry.addRestakingMiddleware(address(middleware));
        vm.stopPrank();
    }

    function testRegisterOperator() public {
        address operator = makeAddr("operator");
        string memory rpcEndpoint = "http://localhost:8545";
        registry.registerOperator(operator, rpcEndpoint, address(middleware));
    }
}
