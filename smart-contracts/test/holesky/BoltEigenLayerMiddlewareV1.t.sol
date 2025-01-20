// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts-eigenlayer/token/ERC20/IERC20.sol";
import {
    IAllocationManager, IAllocationManagerTypes
} from "@eigenlayer/src/contracts/interfaces/IAllocationManager.sol";
import {IDelegationManager} from "@eigenlayer/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "@eigenlayer/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "@eigenlayer/src/contracts/interfaces/IStrategy.sol";
import {ISignatureUtils} from "@eigenlayer/src/contracts/interfaces/ISignatureUtils.sol";
import {OperatorSet} from "@eigenlayer/src/contracts/libraries/OperatorSetLib.sol";

import {OperatorsRegistryV1} from "../../src/holesky/contracts/OperatorsRegistryV1.sol";
import {IOperatorsRegistryV1} from "../../src/holesky/interfaces/IOperatorsRegistryV1.sol";
import {BoltEigenLayerMiddlewareV1} from "../../src/holesky/contracts/BoltEigenLayerMiddlewareV1.sol";

contract BoltEigenLayerMiddlewareV1Test is Test {
    OperatorsRegistryV1 registry;
    BoltEigenLayerMiddlewareV1 middleware;

    address admin;
    address operator;
    address staker;

    IAllocationManager holeskyAllocationManager = IAllocationManager(0x78469728304326CBc65f8f95FA756B0B73164462);
    IDelegationManager holeskyDelegationManager = IDelegationManager(0xA44151489861Fe9e3055d95adC98FbD462B948e7);
    IStrategyManager holeskyStrategyManager = IStrategyManager(0xdfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6);

    // StEth Proxy: 0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034
    IERC20 holeskyStEth = IERC20(0x59034815464d18134A55EED3702b535D8A32c52b);
    IStrategy holeskyStEthStrategy = IStrategy(0x7D704507b76571a51d9caE8AdDAbBFd0ba0e63d3);

    // Note: operator signature check can be skipped for testing purposes. This is a no-op signature.
    ISignatureUtils.SignatureWithExpiry NoOpSignature = ISignatureUtils.SignatureWithExpiry(bytes(""), 0);

    function setUp() public {
        vm.createSelectFork("https://geth-holesky.bolt.chainbound.io");

        admin = makeAddr("admin");
        operator = makeAddr("operator");
        staker = makeAddr("staker");

        vm.deal(admin, 1000 ether);
        vm.deal(staker, 1000 ether);

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
        middleware.addStrategyToWhitelist(address(holeskyStEthStrategy));

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = holeskyStEthStrategy;

        IAllocationManagerTypes.CreateSetParams[] memory createParams = new IAllocationManagerTypes.CreateSetParams[](1);
        createParams[0] = IAllocationManagerTypes.CreateSetParams({operatorSetId: 0, strategies: strategies});

        // 2. Create an OperatorSet in the middleware (with the stEth strategy)
        middleware.createOperatorSets(createParams);

        // 3. Add the middleware address to the registry
        registry.updateRestakingMiddleware("EIGENLAYER", address(middleware));

        // 4. Update the metadata URI
        middleware.updateAVSMetadataURI("https://grugbrain.dev");

        vm.stopPrank();
    }

    /// Helper function to register an operator
    function _registerOperator(address signer, string memory rpcEndpoint) public {
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

    function testRegisterOperator() public {
        string memory rpcEndpoint = "http://localhost:8545";

        _registerOperator(operator, rpcEndpoint);
    }

    function testDepositCollateral() public {
        string memory rpcEndpoint = "http://localhost:8545";

        // 0. Mint stEth to the staker
        // TODO

        // 1. Deposit stEth collateral to the operator
        vm.prank(staker);
        holeskyStEth.approve(address(holeskyStrategyManager), 100 ether);
        vm.prank(staker);
        uint256 shares = holeskyStrategyManager.depositIntoStrategy(holeskyStEthStrategy, holeskyStEth, 100 ether);
        assertEq(holeskyStEthStrategy.sharesToUnderlyingView(shares), 100 ether);

        // 2. Register the operator in both EL and the bolt AVS
        _registerOperator(operator, rpcEndpoint);

        // 3. Delegate funds from the staker to the operator
        vm.prank(staker);
        holeskyDelegationManager.delegateTo(operator, NoOpSignature, bytes32(0));
        assertEq(holeskyDelegationManager.delegatedTo(staker), operator);

        // 4. Update operator allocation for the bolt avs

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = holeskyStEthStrategy;

        uint64[] memory newMagnitudes = new uint64[](1);
        newMagnitudes[0] = 100;

        IAllocationManagerTypes.AllocateParams[] memory allocs = new IAllocationManagerTypes.AllocateParams[](1);
        allocs[0] = IAllocationManagerTypes.AllocateParams({
            operatorSet: OperatorSet(address(middleware), 0), // opSet id = 0
            strategies: strategies,
            newMagnitudes: newMagnitudes
        });

        vm.prank(operator);
        holeskyAllocationManager.modifyAllocations(operator, allocs);

        // 5. try to read the operator's collateral directly on the avs
        (address[] memory collaterals, uint256[] memory amounts) = middleware.getOperatorCollaterals(operator);
        assertEq(collaterals.length, 1);
        assertEq(amounts.length, 1);
        assertEq(collaterals[0], address(holeskyStEth));
    }
}
