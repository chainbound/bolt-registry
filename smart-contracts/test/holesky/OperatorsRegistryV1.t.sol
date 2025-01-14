// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {OperatorsRegistryV1} from "../../src/holesky/contracts/OperatorsRegistryV1.sol";

contract OperatorsRegistryTest is Test {
    OperatorsRegistryV1 registry;

    address admin;
    address signer;

    // This should be a valid middleware contract, mocked as EOA for now
    address restakingMiddleware = address(0x2);

    function setUp() public {
        admin = makeAddr("admin");
        signer = makeAddr("signer");

        vm.startPrank(admin);
        registry = new OperatorsRegistryV1();
        registry.initialize(admin);
        registry.addRestakingMiddleware(restakingMiddleware);
        vm.stopPrank();
    }

    function testRegisterOperator() public {
        string memory rpcEndpoint = "http://localhost:8545";

        registry.registerOperator(signer, rpcEndpoint, restakingMiddleware);
    }

    function testRegisterOperatorInvalidMiddleware() public {
        string memory rpcEndpoint = "http://localhost:8545";

        address invalidMiddleware = address(0x1);
        vm.expectRevert("Invalid restaking middleware");
        registry.registerOperator(makeAddr("signer2"), rpcEndpoint, invalidMiddleware);
    }

    function testRegisterOperatorDuplicateSigner() public {
        string memory rpcEndpoint = "http://localhost:8545";

        registry.registerOperator(signer, rpcEndpoint, restakingMiddleware);
        vm.expectRevert("Operator already exists");
        registry.registerOperator(signer, rpcEndpoint, restakingMiddleware);
    }

    function testRegisterOperatorInvalidSigner() public {
        string memory rpcEndpoint = "http://localhost:8545";

        address invalidSigner = address(0x0);
        vm.expectRevert("Invalid operator address");
        registry.registerOperator(invalidSigner, rpcEndpoint, restakingMiddleware);
    }
}
