// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {OperatorsRegistryV1} from "../src/holesky/contracts/OperatorsRegistryV1.sol";

contract OperatorsRegistryTest is Test {
    OperatorsRegistry registry;

    function setUp() public {
        registry = new OperatorsRegistry();
    }
}
