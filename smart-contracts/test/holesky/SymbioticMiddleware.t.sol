// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";

import {OperatorsRegistryV1} from "../../src/holesky/contracts/OperatorsRegistryV1.sol";
import {BoltSymbioticMiddlewareV1} from "../../src/holesky/contracts/BoltSymbioticMiddlewareV1.sol";

import {IOperatorRegistry} from "@symbiotic/core/interfaces/IOperatorRegistry.sol";
import {IOptInService} from "@symbiotic/core/interfaces/service/IOptInService.sol";
import {IVaultFactory} from "@symbiotic/core/interfaces/IVaultFactory.sol";
import {IVault} from "@symbiotic/core/interfaces/vault/IVault.sol";
import {IVaultStorage} from "@symbiotic/core/interfaces/vault/IVaultStorage.sol";
import {INetworkRestakeDelegator} from "@symbiotic/core/interfaces/delegator/INetworkRestakeDelegator.sol";
import {INetworkMiddlewareService} from "@symbiotic/core/interfaces/service/INetworkMiddlewareService.sol";
import {INetworkRegistry} from "@symbiotic/core/interfaces/INetworkRegistry.sol";
import {IBaseDelegator} from "@symbiotic/core/interfaces/delegator/IBaseDelegator.sol";
import {Subnetwork} from "@symbiotic/core/contracts/libraries/Subnetwork.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract SymbioticMiddlewareTest is Test {
    using Subnetwork for address;

    OperatorsRegistryV1 registry;
    BoltSymbioticMiddlewareV1 middleware;

    IVault wstEthVault = IVault(0xd88dDf98fE4d161a66FB836bee4Ca469eb0E4a75);
    IERC20 wstEth = IERC20(0x8d09a4502Cc8Cf1547aD300E066060D043f6982D);

    address admin;
    address network;
    address operator;

    address vaultAdmin = 0xe8616DEcea16b5216e805B0b8caf7784de7570E7;
    address networkMiddlewareService = 0x62a1ddfD86b4c1636759d9286D3A0EC722D086e3;
    address vaultRegistry = 0x407A039D94948484D356eFB765b3c74382A050B4;
    address vaultOptinService = 0x95CC0a052ae33941877c9619835A233D21D57351;
    address operatorRegistry = 0x6F75a4ffF97326A00e52662d82EA4FdE86a2C548;
    address operatorNetOptin = 0x58973d16FFA900D11fC22e5e2B6840d9f7e13401;

    function setUp() public {
        vm.createSelectFork("https://geth-holesky.bolt.chainbound.io");

        admin = makeAddr("admin");
        network = makeAddr("network");
        operator = makeAddr("operator");
        vm.deal(admin, 1000 ether);

        vm.startPrank(admin);

        registry = new OperatorsRegistryV1();
        registry.initialize(admin);

        middleware = new BoltSymbioticMiddlewareV1();
        vm.stopPrank();

        address networkRegistry = INetworkMiddlewareService(networkMiddlewareService).NETWORK_REGISTRY();

        // Register network
        vm.startPrank(network);
        INetworkRegistry(networkRegistry).registerNetwork();

        INetworkMiddlewareService(networkMiddlewareService).setMiddleware(address(middleware));

        middleware.initialize(
            admin, network, address(registry), 0, 0, vaultRegistry, operatorRegistry, operatorNetOptin
        );

        vm.stopPrank();
    }

    function testRegisterOperator() public {
        vm.startPrank(operator);
        // Symbiotic registration
        IOperatorRegistry(operatorRegistry).registerOperator();
        IOptInService(operatorNetOptin).optIn(network);

        // Bolt registration
        middleware.registerOperator();
        vm.stopPrank();

        assertEq(middleware.operatorsLength(), 1);
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

    function testDeposit() public {
        vm.startPrank(admin);
        middleware.whitelistVault(address(wstEthVault));
        vm.stopPrank();

        vm.startPrank(network);
        // Set the max network limit for the vault as the network
        IBaseDelegator(wstEthVault.delegator()).setMaxNetworkLimit(0, 10 ether);
        vm.stopPrank();

        // Set the network limit for this network (as the curator)
        vm.startPrank(vaultAdmin);
        INetworkRestakeDelegator(wstEthVault.delegator()).setNetworkLimit(network.subnetwork(0), 10 ether);

        assertEq(middleware.getOperatorStake(operator, address(wstEth)), 0);

        // Mint operator shares (need to be vault admin / curator)
        INetworkRestakeDelegator(wstEthVault.delegator()).setOperatorNetworkShares(
            network.subnetwork(0), operator, 1 ether
        );
        vm.stopPrank();

        assertEq(
            INetworkRestakeDelegator(wstEthVault.delegator()).operatorNetworkShares(network.subnetwork(0), operator),
            1 ether
        );

        assertEq(
            INetworkRestakeDelegator(wstEthVault.delegator()).totalOperatorNetworkShares(network.subnetwork(0)), 1 ether
        );

        vm.startPrank(operator);

        IOperatorRegistry(operatorRegistry).registerOperator();
        IOptInService(operatorNetOptin).optIn(network);

        IOptInService(vaultOptinService).optIn(address(wstEthVault));

        // --- Add stake to the Vault ---
        deal(address(wstEth), operator, 1 ether);

        wstEth.approve(address(wstEthVault), 1 ether);

        // deposit collateral from "provider" on behalf of "operator"
        (uint256 depositedAmount, uint256 mintedShares) = wstEthVault.deposit(operator, 1 ether);

        assertEq(depositedAmount, 1 ether);
        assertEq(mintedShares, 1 ether);

        assert(wstEth.balanceOf(address(wstEthVault)) >= 1 ether);

        // TODO: why is this different than getOperatorStake below?
        assertEq(wstEthVault.slashableBalanceOf(operator), 1 ether);

        // All stake is active for this operator, because operatorShares == totalShares
        // stake = operatorShares * min(activeStake, networkLimit) / totalShares
        uint256 activeStake = wstEthVault.activeStake();
        assertEq(middleware.getOperatorStake(operator, address(wstEth)), activeStake);
    }
}
