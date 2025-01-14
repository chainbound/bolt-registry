// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script, console} from "forge-std/Script.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Upgrades, Options} from "@openzeppelin/foundry-upgrades/src/Upgrades.sol";

import {BaseMiddlewareReader} from "@symbiotic/middleware-sdk/middleware/BaseMiddlewareReader.sol";

import {SymbioticMiddlewareV1} from "../../src/holesky/contracts/SymbioticMiddlewareV1.sol";

contract DeployRegistry is Script {
    function run() public {
        address admin = msg.sender;
        address readerHelper = address(new BaseMiddlewareReader());

        // TODO: Fix safe deploy, currently failing with `ASTDereferencerError` from openzeppelin
        Options memory opts;
        opts.unsafeSkipAllChecks = true;

        // function initialize(
        //     address owner,
        //     address network,
        //     address networkRegistry,
        //     uint48 slashingWindow,
        //     address vaultRegistry,
        //     address operatorRegistry,
        //     address operatorNetOptin,
        //     address reader
        // ) public initializer {
        bytes memory initParams = abi.encodeCall(
            SymbioticMiddlewareV1.initialize,
            (
                admin,
                admin,
                admin,
                0,
                admin,
                admin,
                admin,
                // TODO
                readerHelper
            )
        );

        address middleware = Upgrades.deployUUPSProxy("SymbioticMiddlewareV1", initParams, opts);
        console.log("Deployed middleware at:", middleware);
    }
}
