// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";

import {OperatorsRegistryV1} from "../../src/contracts/OperatorsRegistryV1.sol";
import {IOperatorsRegistryV1} from "../../src/interfaces/IOperatorsRegistryV1.sol";
import {BoltSymbioticMiddlewareV1} from "../../src/contracts/BoltSymbioticMiddlewareV1.sol";

import {IOperatorRegistry} from "@symbiotic/core/interfaces/IOperatorRegistry.sol";
import {IOptInService} from "@symbiotic/core/interfaces/service/IOptInService.sol";
import {IRegistry} from "@symbiotic/core/interfaces/common/IRegistry.sol";
import {IVaultFactory} from "@symbiotic/core/interfaces/IVaultFactory.sol";
import {IVault} from "@symbiotic/core/interfaces/vault/IVault.sol";
import {IVaultStorage} from "@symbiotic/core/interfaces/vault/IVaultStorage.sol";
import {INetworkRestakeDelegator} from "@symbiotic/core/interfaces/delegator/INetworkRestakeDelegator.sol";
import {INetworkMiddlewareService} from "@symbiotic/core/interfaces/service/INetworkMiddlewareService.sol";
import {IOperatorSpecificDelegator} from "@symbiotic/core/interfaces/delegator/IOperatorSpecificDelegator.sol";
import {INetworkRegistry} from "@symbiotic/core/interfaces/INetworkRegistry.sol";
import {IBaseDelegator} from "@symbiotic/core/interfaces/delegator/IBaseDelegator.sol";
import {Subnetwork} from "@symbiotic/core/contracts/libraries/Subnetwork.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract SymbioticMiddlewareMainnetTest is Test {
    using Subnetwork for address;

    uint48 EPOCH_DURATION = 1 days;

    OperatorsRegistryV1 registry;
    BoltSymbioticMiddlewareV1 middleware;

    IVault wstEthVault = IVault(0xfab8c5483a829f8D92c7e5eCbac586b07c1243Da);
    IERC20 wstEth = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    address admin;
    address network;
    // NOTE: this has to be the operator of the operator-specific wstEthVault
    address operator = 0x9321d38c355d1D8cB9dbfC05a5c0f347b1DDa46a;

    // Possibly?
    address vaultAdmin = 0x9321d38c355d1D8cB9dbfC05a5c0f347b1DDa46a;

    // https://symbioticfi.notion.site/Mainnet-Deployment-Contract-Addresses-17581c079c178051be5ef6cf3cb65288
    address networkMiddlewareService = 0xD7dC9B366c027743D90761F71858BCa83C6899Ad;
    address vaultOptinService = 0xb361894bC06cbBA7Ea8098BF0e32EB1906A5F891;
    IRegistry vaultRegistry = IRegistry(0xAEb6bdd95c502390db8f52c8909F703E9Af6a346);
    IRegistry operatorRegistry = IRegistry(0xAd817a6Bc954F678451A71363f04150FDD81Af9F);
    IOptInService operatorNetOptin = IOptInService(0x7133415b33B438843D581013f98A08704316633c);

    function setUp() public {
        vm.createSelectFork("https://geth-mainnet.bolt.chainbound.io");

        admin = makeAddr("admin");
        network = makeAddr("network");
        vm.deal(admin, 1000 ether);

        vm.startPrank(admin);

        registry = new OperatorsRegistryV1();
        registry.initialize(admin, EPOCH_DURATION);

        middleware = new BoltSymbioticMiddlewareV1();
        middleware.initialize(admin, network, registry, vaultRegistry, operatorRegistry, operatorNetOptin);

        // Set the restaking middleware
        registry.updateRestakingMiddleware("SYMBIOTIC", middleware);

        vm.stopPrank();

        // TODO: reverts with NotActivated?
        // address networkRegistry = INetworkMiddlewareService(networkMiddlewareService).NETWORK_REGISTRY();
        address networkRegistry = 0xC773b1011461e7314CF05f97d95aa8e92C1Fd8aA;

        // Register network
        vm.startPrank(network);
        // TODO: also reverts with NotActived
        INetworkRegistry(networkRegistry).registerNetwork();

        INetworkMiddlewareService(networkMiddlewareService).setMiddleware(address(middleware));

        vm.stopPrank();
    }

    function _prepareNetworkAndVault() public {
        // --- Whitelist vault, activate network on vault ---
        vm.prank(admin);
        // Whitelist the vault
        middleware.whitelistVault(address(wstEthVault));
        // Activate the vault by setting max network limit
        vm.startPrank(network);
        IBaseDelegator(wstEthVault.delegator()).setMaxNetworkLimit(0, 10 ether);
        vm.stopPrank();

        // --- Set network limit for network as curator ---
        vm.startPrank(vaultAdmin);
        IOperatorSpecificDelegator(wstEthVault.delegator()).setNetworkLimit(network.subnetwork(0), 10 ether);

        assertEq(
            IOperatorSpecificDelegator(wstEthVault.delegator()).networkLimit(network.subnetwork(0)),
            10 ether,
            "Network limit should be set"
        );

        assertEq(middleware.getOperatorStake(operator, address(wstEth)), 0);

        // Mint operator shares (need to be vault admin / curator)
        // IOperatorSpecificDelegator(wstEthVault.delegator()).setOperatorNetworkShares(
        //     network.subnetwork(0), operator, 1 ether
        // );

        // assertEq(
        //     IOperatorSpecificDelegator(wstEthVault.delegator()).to(network.subnetwork(0), operator),
        //     1 ether
        // );

        // assertEq(
        //     IOperatorSpecificDelegator(wstEthVault.delegator()).totalOperatorNetworkShares(network.subnetwork(0)),
        //     1 ether
        // );

        vm.stopPrank();
    }

    // This function does the following:
    // - Register the operator in Symbiotic contracts
    // - Opt in to the Bolt network
    // - Deposit collateral in the vault linked to the Bolt network
    function _registerOperatorRoutine() public {
        vm.startPrank(operator);

        // NOTE: operator already registered
        // IOperatorRegistry(operatorRegistry).registerOperator();
        IOptInService(operatorNetOptin).optIn(network);

        IOptInService(vaultOptinService).optIn(address(wstEthVault));

        // --- Add stake to the Vault ---
        deal(address(wstEth), operator, 1 ether);

        wstEth.approve(address(wstEthVault), 1 ether);

        // deposit collateral from "provider" on behalf of "operator"
        (uint256 depositedAmount, uint256 mintedShares) = wstEthVault.deposit(operator, 1 ether);

        assertEq(depositedAmount, 1 ether);
        assertEq(mintedShares, 1 ether);

        vm.stopPrank();
    }

    function testRegisterOperatorNoCollateral() public {
        vm.startPrank(operator);
        // Symbiotic registration
        // NOTE: operator already registered
        // IOperatorRegistry(operatorRegistry).registerOperator();
        IOptInService(operatorNetOptin).optIn(network);

        // Bolt registration
        vm.expectEmit();
        emit IOperatorsRegistryV1.OperatorRegistered(
            operator, "https://rpc.boltprotocol.xyz", address(middleware), "BOLT"
        );

        middleware.registerOperator("https://rpc.boltprotocol.xyz", "BOLT");

        assert(registry.isOperator(operator));

        // Activation requires a second to have passed
        skip(EPOCH_DURATION);
        assert(registry.isActiveOperator(operator));

        vm.stopPrank();
    }

    function testDeregisterOperator() public {
        vm.startPrank(operator);
        // Symbiotic registration
        // NOTE: operator already registered
        // IOperatorRegistry(operatorRegistry).registerOperator();
        IOptInService(operatorNetOptin).optIn(network);

        // Bolt registration
        vm.expectEmit();
        emit IOperatorsRegistryV1.OperatorRegistered(
            operator, "https://rpc.boltprotocol.xyz", address(middleware), "BOLT"
        );

        middleware.registerOperator("https://rpc.boltprotocol.xyz", "BOLT");

        // Activation requires a second to have passed
        skip(EPOCH_DURATION);
        assert(registry.isActiveOperator(operator));

        // This will actually pause the operator instantly
        middleware.deregisterOperator();

        assert(!registry.isActiveOperator(operator));

        // We may not clean up before an epoch has passed
        skip(EPOCH_DURATION - 1);
        registry.cleanup();
        assert(registry.isOperator(operator));

        // Should only be able to clean up AFTER an epoch duration has passed
        skip(1);
        registry.cleanup();
        assert(!registry.isOperator(operator));
    }

    function testCleanup() public {
        vm.startPrank(operator);
        // Symbiotic registration
        // NOTE: operator already registered
        // IOperatorRegistry(operatorRegistry).registerOperator();
        IOptInService(operatorNetOptin).optIn(network);

        // Bolt registration
        vm.expectEmit();
        emit IOperatorsRegistryV1.OperatorRegistered(
            operator, "https://rpc.boltprotocol.xyz", address(middleware), "BOLT"
        );

        middleware.registerOperator("https://rpc.boltprotocol.xyz", "BOLT");

        // Activation requires a second to have passed
        skip(EPOCH_DURATION);
        assert(registry.isActiveOperator(operator));

        middleware.deregisterOperator();

        skip(EPOCH_DURATION);
        // Clean up is only possible EPOCH_DURATION after deregistation
        registry.cleanup();
        assert(!registry.isOperator(operator));
    }

    function testWhitelistVault() public {
        vm.startPrank(admin);
        // Symbiotic registration

        // Bolt registration
        vm.expectRevert(BoltSymbioticMiddlewareV1.NotVault.selector);
        middleware.whitelistVault(address(0));

        middleware.whitelistVault(address(wstEthVault));
        assertEq(middleware.vaultWhitelistLength(), 1);

        vm.stopPrank();
    }

    function testRemoveVault() public {
        vm.startPrank(admin);

        middleware.whitelistVault(address(wstEthVault));
        assertEq(middleware.vaultWhitelistLength(), 1);

        middleware.pauseVault(address(wstEthVault));
        // Pausing takes a sec
        assertEq(middleware.isVaultActive(address(wstEthVault)), false, "Vault should be inactive");

        skip(EPOCH_DURATION - 1);
        vm.expectRevert();
        middleware.removeVault(address(wstEthVault));

        // To remove, we need to pass the immutable period (EPOCH_DURATION)
        skip(1);
        middleware.removeVault(address(wstEthVault));
        assertEq(middleware.vaultWhitelistLength(), 0);
    }

    function testDeposit() public {
        _prepareNetworkAndVault();
        _registerOperatorRoutine();

        assertTrue(
            wstEth.balanceOf(address(wstEthVault)) >= 1 ether, "Vault balance should be higher than or equal to 1 ether"
        );

        // TODO: why is this different than getOperatorStake below?
        assertEq(wstEthVault.slashableBalanceOf(operator), 1 ether, "Slashable balance of operator should be 1 ether");

        // All stake is active for this operator, because operatorShares == totalShares
        // stake = operatorShares * min(activeStake, networkLimit) / totalShares
        uint256 activeStake = wstEthVault.activeStake();
        console.log("Active stake: ", activeStake);
        assertEq(
            middleware.getOperatorStake(operator, address(wstEth)),
            activeStake,
            "getOperatorStake should be equal to activeStake"
        );
    }

    // This function tests whether pausing a vault actually deactivates the collateral
    function testDeactivateCollateral() public {
        _prepareNetworkAndVault();
        _registerOperatorRoutine();

        // All stake is active for this operator, because operatorShares == totalShares
        // stake = operatorShares * min(activeStake, networkLimit) / totalShares
        uint256 activeStake = wstEthVault.activeStake();
        assertEq(middleware.getOperatorStake(operator, address(wstEth)), activeStake);

        // Pause the vault
        vm.prank(admin);
        middleware.pauseVault(address(wstEthVault));
        assertEq(middleware.getOperatorStake(operator, address(wstEth)), 0);
    }

    function testGetCollaterals() public {
        _prepareNetworkAndVault();
        _registerOperatorRoutine();

        // Only 1 whitelisted collateral -> array len will be 1
        (address[] memory collaterals, uint256[] memory amounts) = middleware.getOperatorCollaterals(operator);

        assertEq(collaterals.length, 1);
        assert(amounts[0] >= 1 ether);

        vm.prank(admin);
        middleware.pauseVault(address(wstEthVault));

        (collaterals, amounts) = middleware.getOperatorCollaterals(operator);
        assertEq(collaterals.length, 1);
        assert(amounts[0] == 0);
    }
}
