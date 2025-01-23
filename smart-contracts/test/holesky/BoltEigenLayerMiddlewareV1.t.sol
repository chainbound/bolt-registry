// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts-eigenlayer/token/ERC20/IERC20.sol";
import {
    IAllocationManager, IAllocationManagerTypes
} from "@eigenlayer/src/contracts/interfaces/IAllocationManager.sol";
import {AllocationManagerStorage} from "@eigenlayer/src/contracts/core/AllocationManagerStorage.sol";
import {IDelegationManager} from "@eigenlayer/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "@eigenlayer/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "@eigenlayer/src/contracts/interfaces/IStrategy.sol";
import {ISignatureUtils} from "@eigenlayer/src/contracts/interfaces/ISignatureUtils.sol";
import {IAVSDirectory} from "@eigenlayer/src/contracts/interfaces/IAVSDirectory.sol";
import {OperatorSet} from "@eigenlayer/src/contracts/libraries/OperatorSetLib.sol";
import {PauseableEnumerableSet} from "@symbiotic/middleware-sdk/libraries/PauseableEnumerableSet.sol";

import {OperatorsRegistryV1} from "../../src/holesky/contracts/OperatorsRegistryV1.sol";
import {IOperatorsRegistryV1} from "../../src/holesky/interfaces/IOperatorsRegistryV1.sol";
import {BoltEigenLayerMiddlewareV1} from "../../src/holesky/contracts/BoltEigenLayerMiddlewareV1.sol";
import {IWETH} from "../util/IWETH.sol";

contract BoltEigenLayerMiddlewareV1Test is Test {
    OperatorsRegistryV1 registry;
    BoltEigenLayerMiddlewareV1 middleware;

    address admin;
    address staker;
    address operator;
    uint256 operatorSk;

    IAllocationManager holeskyAllocationManager = IAllocationManager(0x78469728304326CBc65f8f95FA756B0B73164462);
    IDelegationManager holeskyDelegationManager = IDelegationManager(0xA44151489861Fe9e3055d95adC98FbD462B948e7);
    IStrategyManager holeskyStrategyManager = IStrategyManager(0xdfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6);
    IAVSDirectory holeskyAVSDirectory = IAVSDirectory(0x055733000064333CaDDbC92763c58BF0192fFeBf);

    IERC20 holeskyStEth = IERC20(0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034);
    IStrategy holeskyStEthStrategy = IStrategy(0x7D704507b76571a51d9caE8AdDAbBFd0ba0e63d3);

    IERC20 holeskyWeth = IERC20(0x94373a4919B3240D86eA41593D5eBa789FEF3848);
    IStrategy holeskyWethStrategy = IStrategy(0x80528D6e9A2BAbFc766965E0E26d5aB08D9CFaF9);

    IERC20 holeskycbEth = IERC20(0x8720095Fa5739Ab051799211B146a2EEE4Dd8B37);
    IStrategy holeskyCbEthStrategy = IStrategy(0x70EB4D3c164a6B4A5f908D4FBb5a9cAfFb66bAB6);

    // Note: operators can gate staker delegations behind a signature check. when this is disabled,
    // a signature is still required but it can be empty. This is a no-op signature.
    ISignatureUtils.SignatureWithExpiry NoOpSignature = ISignatureUtils.SignatureWithExpiry(bytes(""), 0);

    function setUp() public {
        vm.createSelectFork("https://geth-holesky.bolt.chainbound.io");

        admin = makeAddr("admin");
        staker = makeAddr("staker");
        (operator, operatorSk) = makeAddrAndKey("operator");

        vm.startPrank(admin);

        // --- Deploy the OperatorsRegistry ---
        registry = new OperatorsRegistryV1();
        registry.initialize(admin, 1 days);

        // --- Deploy the EL middleware ---
        middleware = new BoltEigenLayerMiddlewareV1();
        middleware.initialize(
            admin,
            holeskyAVSDirectory,
            holeskyAllocationManager,
            holeskyDelegationManager,
            holeskyStrategyManager,
            registry
        );

        // 1. Whitelist the strategies in the middleware
        middleware.whitelistStrategy(address(holeskyStEthStrategy));
        middleware.whitelistStrategy(address(holeskyWethStrategy));

        // check that the strategies are whitelisted
        IStrategy[] memory whitelistedStrategies = middleware.getActiveWhitelistedStrategies();
        assertEq(whitelistedStrategies.length, 2);
        assertEq(address(whitelistedStrategies[0]), address(holeskyStEthStrategy));
        assertEq(address(whitelistedStrategies[1]), address(holeskyWethStrategy));

        IStrategy[] memory strategies = new IStrategy[](2);
        strategies[0] = holeskyStEthStrategy;
        strategies[1] = holeskyWethStrategy;

        IAllocationManagerTypes.CreateSetParams[] memory createParams = new IAllocationManagerTypes.CreateSetParams[](1);
        createParams[0] = IAllocationManagerTypes.CreateSetParams({operatorSetId: 0, strategies: strategies});

        // 2. Create an OperatorSet in the middleware to handle all strategies
        middleware.createOperatorSets(createParams);

        // 3. Add the middleware address to the registry
        registry.updateRestakingMiddleware("EIGENLAYER", middleware);

        // 4. Update the metadata URI
        middleware.updateAVSMetadataURI("ALLOCATION_MANAGER", "https://grugbrain.dev");

        vm.stopPrank();
    }

    /// Helper function to register an operator
    function _registerOperator(address signer, string memory rpcEndpoint, string memory extraData) public {
        // 1. Register the new EL operator in DelegationManager
        uint32 allocationDelay = 1;
        address delegationApprover = address(0x0); // this is optional, skip it
        string memory uri = "some-meetadata.uri.com";
        vm.prank(signer);
        holeskyDelegationManager.registerAsOperator(delegationApprover, allocationDelay, uri);

        // 2. Register the operator in the bolt AVS
        vm.prank(signer);
        holeskyAllocationManager.registerForOperatorSets(
            signer,
            IAllocationManagerTypes.RegisterParams({
                avs: address(middleware),
                operatorSetIds: new uint32[](0), // specify the newly created operator set
                data: abi.encode(rpcEndpoint, extraData)
            })
        );

        // 3. make sure to enable allocations by skipping the builtin delay blocks
        uint32 delay = AllocationManagerStorage(address(holeskyAllocationManager)).ALLOCATION_CONFIGURATION_DELAY();
        vm.roll(block.number + delay + 1);
    }

    function testRegister() public {
        _registerOperator(operator, "http://stopjava.com", "operator1");
    }

    function testRegisterAndDepositCollateral() public {
        // 0. Mint weth to the staker
        assertEq(address(holeskyWethStrategy.underlyingToken()), address(holeskyWeth));
        vm.deal(staker, 100 ether);
        vm.prank(staker);
        IWETH(address(holeskyWeth)).deposit{value: 100 ether}();
        assertEq(holeskyWeth.balanceOf(staker), 100 ether);

        // 1. Deposit weth collateral to the operator
        vm.prank(staker);
        holeskyWeth.approve(address(holeskyStrategyManager), 100 ether);
        vm.prank(staker);
        uint256 shares = holeskyStrategyManager.depositIntoStrategy(holeskyWethStrategy, holeskyWeth, 100 ether);
        assertEq(holeskyWethStrategy.sharesToUnderlyingView(shares), 100 ether);

        // 2. Register the operator in both EL and the bolt AVS
        _registerOperator(operator, "http://stopjava.com", "operator1");

        // 3. Delegate funds from the staker to the operator
        vm.prank(staker);
        holeskyDelegationManager.delegateTo(operator, NoOpSignature, bytes32(0));
        assertEq(holeskyDelegationManager.delegatedTo(staker), operator);

        // 4. Update operator allocation for the bolt avs

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = holeskyWethStrategy;

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

        // make sure the strategies are active in the middleware
        IStrategy[] memory activeStrats = middleware.getActiveWhitelistedStrategies();
        assertEq(activeStrats.length, 2);

        // 5. try to read the operator's collateral directly on the avs
        (address[] memory collaterals, uint256[] memory amounts) = middleware.getOperatorCollaterals(operator);
        assertEq(collaterals.length, 2);
        assertEq(amounts.length, 2);

        // stEth should have 0 balance
        assertEq(collaterals[0], address(holeskyStEth));
        assertEq(amounts[0], 0);

        // weth should have 100e18 balance
        assertEq(collaterals[1], address(holeskyWeth));
        assertEq(amounts[1], 100 ether);
    }

    function testCannotAddAlreadyWhitelistedStrategy() public {
        vm.prank(admin);
        vm.expectRevert(BoltEigenLayerMiddlewareV1.StrategyAlreadyWhitelisted.selector);
        middleware.whitelistStrategy(address(holeskyStEthStrategy));
    }

    function testCannotAddInvalidStrategyAddress() public {
        vm.prank(admin);
        vm.expectRevert(BoltEigenLayerMiddlewareV1.InvalidStrategyAddress.selector);
        middleware.whitelistStrategy(address(0));
    }

    function testCannotAddOperatorSetWithNonWhitelistedStrategy() public {
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = IStrategy(address(holeskyCbEthStrategy));

        IAllocationManagerTypes.CreateSetParams[] memory createParams = new IAllocationManagerTypes.CreateSetParams[](1);
        createParams[0] = IAllocationManagerTypes.CreateSetParams({operatorSetId: 1, strategies: strategies});

        vm.prank(admin);
        vm.expectRevert(BoltEigenLayerMiddlewareV1.UnauthorizedStrategy.selector);
        middleware.createOperatorSets(createParams);
    }

    function testCannotRemoveNonWhitelistedStrategy() public {
        vm.prank(admin);
        vm.expectRevert(BoltEigenLayerMiddlewareV1.UnauthorizedStrategy.selector);
        middleware.removeStrategy(address(holeskyCbEthStrategy));
    }

    function testCannotRemoveUnpausedStrategy() public {
        vm.prank(admin);
        vm.expectRevert(PauseableEnumerableSet.Enabled.selector);
        middleware.removeStrategy(address(holeskyStEthStrategy));
    }

    function testMustWaitImmutablePeriodBeforeRemovingStrategy() public {
        vm.prank(admin);
        middleware.pauseStrategy(address(holeskyStEthStrategy));

        vm.prank(admin);
        vm.expectRevert(PauseableEnumerableSet.ImmutablePeriodNotPassed.selector);
        middleware.removeStrategy(address(holeskyStEthStrategy));

        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(admin);
        middleware.removeStrategy(address(holeskyStEthStrategy));
    }

    function testCannotUseAllocationManagerIfNotSet() public {
        vm.prank(admin);
        middleware.updateAllocationManagerAddress(address(0));

        // When the AllocationManager is set to 0x0, the only way to opt-in
        // is through the middeware.registerThroughAVSDirectory() method.

        uint32 allocationDelay = 1;
        address delegationApprover = address(0x0); // this is optional, skip it
        string memory uri = "some-meetadata.uri.com";
        vm.prank(operator);
        holeskyDelegationManager.registerAsOperator(delegationApprover, allocationDelay, uri);

        vm.prank(operator);
        vm.expectRevert(BoltEigenLayerMiddlewareV1.NotAllocationManager.selector);
        holeskyAllocationManager.registerForOperatorSets(
            operator,
            IAllocationManagerTypes.RegisterParams({
                avs: address(middleware),
                operatorSetIds: new uint32[](0),
                data: abi.encode("")
            })
        );
    }

    function testCannotRegisterThroughAVSDirectoryIfNotOperator() public {
        bytes32 operatorRegistrationDigestHash = holeskyAVSDirectory.calculateOperatorAVSRegistrationDigestHash({
            operator: operator,
            avs: address(middleware),
            salt: bytes32(0),
            expiry: UINT256_MAX
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorSk, operatorRegistrationDigestHash);
        bytes memory operatorRawSignature = abi.encodePacked(r, s, v);
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature =
            ISignatureUtils.SignatureWithSaltAndExpiry(operatorRawSignature, bytes32(0), UINT256_MAX);

        vm.prank(operator);
        vm.expectRevert(BoltEigenLayerMiddlewareV1.NotOperator.selector);
        middleware.registerThroughAVSDirectory("http://stopjava.com", "operator1", operatorSignature);
    }
}
