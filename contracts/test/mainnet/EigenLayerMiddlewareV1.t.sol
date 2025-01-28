// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin-v4.9.0/contracts/token/ERC20/IERC20.sol";
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

import {OperatorsRegistryV1} from "../../src/contracts/OperatorsRegistryV1.sol";
import {IOperatorsRegistryV1} from "../../src/interfaces/IOperatorsRegistryV1.sol";
import {EigenLayerMiddlewareV1} from "../../src/contracts/EigenLayerMiddlewareV1.sol";

// This is needed because the registerAsOperator function has changed in ELIP-002
// and we need to manually call it with the pre-ELIP-002 parameters
interface IDelegationManagerPreELIP002 {
    struct OperatorDetails {
        address __deprecated_earningsReceiver;
        address delegationApprover;
        uint32 stakerOptOutWindowBlocks;
    }

    function registerAsOperator(
        OperatorDetails calldata registeringOperatorDetails,
        string calldata metadataURI
    ) external;
}

contract EigenLayerMiddlewareV1Test is Test {
    OperatorsRegistryV1 registry;
    EigenLayerMiddlewareV1 middleware;

    address admin;
    address staker;
    address operator;
    uint256 operatorSk;

    IDelegationManager mainnetDelegationManager = IDelegationManager(0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A);
    IStrategyManager mainnetStrategyManager = IStrategyManager(0x858646372CC42E1A627fcE94aa7A7033e7CF075A);
    IAVSDirectory mainnetAVSDirectory = IAVSDirectory(0x135DDa560e946695d6f155dACaFC6f1F25C1F5AF);

    IERC20 mainnetCbEth = IERC20(0xBe9895146f7AF43049ca1c1AE358B0541Ea49704);
    IStrategy mainnetCbEthStrategy = IStrategy(0x54945180dB7943c0ed0FEE7EdaB2Bd24620256bc);

    // Note: operators can gate staker delegations behind a signature check. when this is disabled,
    // a signature is still required but it can be empty. This is a no-op signature.
    ISignatureUtils.SignatureWithExpiry NoOpSignature = ISignatureUtils.SignatureWithExpiry(bytes(""), 0);

    function setUp() public {
        vm.createSelectFork("https://geth-mainnet.bolt.chainbound.io");

        admin = makeAddr("admin");
        staker = makeAddr("staker");
        (operator, operatorSk) = makeAddrAndKey("operator");

        vm.startPrank(admin);

        // --- Deploy the OperatorsRegistry ---
        registry = new OperatorsRegistryV1();
        registry.initialize(admin, 1 days);

        // --- Deploy the EL middleware ---
        middleware = new EigenLayerMiddlewareV1();
        middleware.initialize(
            admin,
            registry,
            mainnetAVSDirectory,
            IAllocationManager(address(0)),
            mainnetDelegationManager,
            mainnetStrategyManager
        );

        // 1. Whitelist the strategies in the middleware
        middleware.whitelistStrategy(address(mainnetCbEthStrategy));

        // check that the strategies are whitelisted
        IStrategy[] memory whitelistedStrategies = middleware.getActiveWhitelistedStrategies();
        assertEq(whitelistedStrategies.length, 1);
        assertEq(address(whitelistedStrategies[0]), address(mainnetCbEthStrategy));

        // IStrategy[] memory strategies = new IStrategy[](1);
        // strategies[0] = mainnetStEthStrategy;

        // IAllocationManagerTypes.CreateSetParams[] memory createParams = new IAllocationManagerTypes.CreateSetParams[](1);
        // createParams[0] = IAllocationManagerTypes.CreateSetParams({operatorSetId: 0, strategies: strategies});

        // // 2. Create an OperatorSet in the middleware to handle all strategies
        // middleware.createOperatorSets(createParams);

        // 3. Add the middleware address to the registry
        registry.updateRestakingMiddleware("EIGENLAYER", middleware);

        // 4. Update the metadata URI
        middleware.updateAVSMetadataURI("AVS_DIRECTORY", "https://grugbrain.dev");

        vm.stopPrank();
    }

    /// Helper function to register an operator
    function _registerOperator(address signer, string memory rpcEndpoint, string memory extraData) public {
        // 1. Register the new EL operator in DelegationManager
        // manually call the registerAsOperator function with the pre-ELIP-002 parameters
        address earningsReceiver = address(1);
        address delegationApprover = address(0);
        uint32 stakerOptOutWindowBlocks = 0;
        vm.prank(signer);
        IDelegationManagerPreELIP002(address(mainnetDelegationManager)).registerAsOperator(
            IDelegationManagerPreELIP002.OperatorDetails(earningsReceiver, delegationApprover, stakerOptOutWindowBlocks),
            "https://some-meetadata.uri.com"
        );

        // 2. As a operator, I can now opt-in into an AVS by interacting with the ServiceManager.
        // Two steps happen:
        // i. I call the AVS’ ServiceManager.registerOperatorToAVS. The payload is a signature whose digest consists of:
        //     a. my operator address
        //     b. the AVS’ ServiceManager contract address
        //     c. a salt
        //     d. an expiry
        // ii. The contract forwards the call to the AVSDirectory.registerOperatorToAVS to
        // that msg.sender is the AVS contract. Upon successful verification of the signature,
        // the operator is considered REGISTERED in a mapping avsOperatorStatus[msg.sender][operator].

        // Calculate the digest hash
        bytes32 operatorRegistrationDigestHash = mainnetAVSDirectory.calculateOperatorAVSRegistrationDigestHash({
            operator: signer,
            avs: address(middleware),
            salt: bytes32(0),
            expiry: UINT256_MAX
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorSk, operatorRegistrationDigestHash);
        bytes memory operatorRawSignature = abi.encodePacked(r, s, v);
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature =
            ISignatureUtils.SignatureWithSaltAndExpiry(operatorRawSignature, bytes32(0), UINT256_MAX);

        vm.prank(signer);
        middleware.registerOperatorToAVS(rpcEndpoint, extraData, operatorSignature);

        vm.warp(block.timestamp + 1 days);

        (IOperatorsRegistryV1.Operator memory opData, bool isActive) = registry.getOperator(signer);
        assertEq(opData.signer, signer);
        assertEq(opData.rpcEndpoint, rpcEndpoint);
        assertEq(opData.extraData, extraData);
        assertEq(opData.restakingMiddleware, address(middleware));
        assertEq(isActive, true);
    }

    function testRegister() public {
        _registerOperator(operator, "http://stopjava.com", "operator1");
    }

    function testRegisterAndDepositCollateral() public {
        // 0. Mint steth to the staker
        assertEq(address(mainnetCbEthStrategy.underlyingToken()), address(mainnetCbEth));
        deal(address(mainnetCbEth), staker, 100 ether);
        assertEq(mainnetCbEth.balanceOf(staker), 100 ether);

        // 1. Deposit weth collateral to the operator
        vm.prank(staker);
        mainnetCbEth.approve(address(mainnetStrategyManager), 100 ether);
        vm.prank(staker);
        uint256 shares = mainnetStrategyManager.depositIntoStrategy(mainnetCbEthStrategy, mainnetCbEth, 100 ether);
        assertEq(mainnetCbEthStrategy.sharesToUnderlyingView(shares), 99_999_999_999_999_999_999);

        // 2. Register the operator in both EL and the bolt AVS
        _registerOperator(operator, "http://stopjava.com", "operator1");

        // 3. Delegate funds from the staker to the operator
        vm.prank(staker);
        mainnetDelegationManager.delegateTo(operator, NoOpSignature, bytes32(0));
        assertEq(mainnetDelegationManager.delegatedTo(staker), operator);

        // make sure the strategies are active in the middleware
        IStrategy[] memory activeStrats = middleware.getActiveWhitelistedStrategies();
        assertEq(activeStrats.length, 1);
        assertEq(address(activeStrats[0]), address(mainnetCbEthStrategy));

        // 5. try to read the operator's collateral directly on the avs
        (address[] memory collaterals, uint256[] memory amounts) = middleware.getOperatorCollaterals(operator);
        assertEq(collaterals.length, 1);
        assertEq(amounts.length, 1);
        assertEq(collaterals[0], address(mainnetCbEth));
        assertEq(amounts[0], 99_999_999_999_999_999_999);
    }
}
