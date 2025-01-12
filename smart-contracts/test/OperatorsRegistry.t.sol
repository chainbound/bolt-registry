// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {OperatorsRegistry} from "../src/contracts/OperatorsRegistry.sol";

contract OperatorsRegistryTest is Test {
    OperatorsRegistry registry;

    function setUp() public {
        registry = new OperatorsRegistry();
    }
}
