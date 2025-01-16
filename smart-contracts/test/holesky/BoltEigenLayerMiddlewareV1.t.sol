// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {
    IAllocationManager, IAllocationManagerTypes
} from "@eigenlayer/src/contracts/interfaces/IAllocationManager.sol";
import {IDelegationManager} from "@eigenlayer/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "@eigenlayer/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "@eigenlayer/src/contracts/interfaces/IStrategy.sol";

import {OperatorsRegistryV1} from "../../src/holesky/contracts/OperatorsRegistryV1.sol";
import {IOperatorsRegistryV1} from "../../src/holesky/interfaces/IOperatorsRegistryV1.sol";
import {BoltEigenLayerMiddlewareV1} from "../../src/holesky/contracts/BoltEigenLayerMiddlewareV1.sol";

contract BoltEigenLayerMiddlewareV1Test is Test {
    OperatorsRegistryV1 registry;
    BoltEigenLayerMiddlewareV1 middleware;

    address admin;
    address operator;

    IAllocationManager holeskyAllocationManager = IAllocationManager(0x78469728304326CBc65f8f95FA756B0B73164462);
    IDelegationManager holeskyDelegationManager = IDelegationManager(0xA44151489861Fe9e3055d95adC98FbD462B948e7);
    IStrategyManager holeskyStrategyManager = IStrategyManager(0xdfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6);

    address holeskyStEthStrategy = 0x7D704507b76571a51d9caE8AdDAbBFd0ba0e63d3;

    function setUp() public {
        vm.createSelectFork("https://geth-holesky.bolt.chainbound.io");

        admin = makeAddr("admin");
        operator = makeAddr("operator");
        vm.deal(admin, 1000 ether);

        vm.startPrank(admin);

        // --- Deploy the OperatorsRegistry ---
        registry = new OperatorsRegistryV1();
        registry.initialize(admin);

        // --- Deploy the EL middleware ---
        middleware = new BoltEigenLayerMiddlewareV1();
        middleware.initialize(
            admin, holeskyAllocationManager, holeskyDelegationManager, holeskyStrategyManager, registry
        );

        // 1. Whitelist the strategy in the middleware
        middleware.addStrategyToWhitelist(holeskyStEthStrategy);

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = IStrategy(holeskyStEthStrategy);

        IAllocationManagerTypes.CreateSetParams[] memory createParams = new IAllocationManagerTypes.CreateSetParams[](1);
        createParams[0] = IAllocationManagerTypes.CreateSetParams({operatorSetId: 0, strategies: strategies});

        // 2. Create an OperatorSet in the middleware (with the stEth strategy)
        middleware.createOperatorSets(createParams);

        // 3. Add the middleware address to the registry
        registry.updateRestakingMiddleware("EIGENLAYER", address(middleware));
        vm.stopPrank();
    }

    function testRegisterOperator() public {
        string memory rpcEndpoint = "http://localhost:8545";

        // 1. Register the new EL operator in DelegationManager
        vm.prank(operator);
        holeskyDelegationManager.registerAsOperator(address(0x0), 0, "my-metadata-uri.com");

        // 2. Register the operator in the bolt AVS
        vm.prank(operator);
        holeskyAllocationManager.registerForOperatorSets(
            operator,
            IAllocationManagerTypes.RegisterParams({
                avs: address(middleware),
                operatorSetIds: new uint32[](0), // specify the newly created operator set
                data: bytes(rpcEndpoint)
            })
        );
    }
}
