// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {OperatorsRegistryV1} from "../../src/holesky/contracts/OperatorsRegistryV1.sol";
import {IOperatorsRegistryV1} from "../../src/holesky/interfaces/IOperatorsRegistryV1.sol";

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
        registry.updateRestakingMiddleware("EIGANLAYER", restakingMiddleware);
        vm.stopPrank();
    }
}
