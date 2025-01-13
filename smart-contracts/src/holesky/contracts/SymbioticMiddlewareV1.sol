// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {BaseMiddleware} from "@symbiotic/middleware-sdk/middleware/BaseMiddleware.sol";
import {OwnableAccessManager} from "@symbiotic/middleware-sdk/extensions/managers/access/OwnableAccessManager.sol";

// import {Subnetwork} from "@symbiotic/contracts/libraries/Subnetwork.sol";

contract SymbioticMiddlewareV1 is BaseMiddleware, OwnableUpgradeable, UUPSUpgradeable {
    using Subnetwork for address;
}
