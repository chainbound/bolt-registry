// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script, console} from "forge-std/Script.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Upgrades, Options} from "@openzeppelin/foundry-upgrades/src/Upgrades.sol";

import {BaseMiddlewareReader} from "@symbiotic/middleware-sdk/middleware/BaseMiddlewareReader.sol";

import {BoltSymbioticMiddlewareV1} from "../../src/holesky/contracts/BoltSymbioticMiddlewareV1.sol";

contract DeployRegistry is Script {
    function run() public {
        address admin = msg.sender;
        address readerHelper = address(new BaseMiddlewareReader());

        // TODO: Fix safe deploy, currently failing with `ASTDereferencerError` from openzeppelin
        Options memory opts;
        opts.unsafeSkipAllChecks = true;

        // TODO:
        // bytes memory initParams = abi.encodeCall(BoltSymbioticMiddlewareV1.initialize, ());

        // address middleware = Upgrades.deployUUPSProxy("SymbioticMiddlewareV1", initParams, opts);
        // console.log("Deployed middleware at:", middleware);
    }
}
