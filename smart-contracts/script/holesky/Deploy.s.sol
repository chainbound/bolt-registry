// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script, console} from "forge-std/Script.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Upgrades, Options} from "@openzeppelin-foundry-upgrades/src/Upgrades.sol";

contract DeployRegistry is Script {
    function main() public {
        address registry = deploy("OperatorsRegistryV1");
        console.log("Registry deployed at: ", registry);
    }
}
