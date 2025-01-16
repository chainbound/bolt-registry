// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title IBoltResakingMiddlewareV1
/// @notice An interface for generalized restaking protocol middlewares in Bolt
interface IBoltResakingMiddlewareV1 {
    function getOperatorCollaterals(
        address operator
    ) external view returns (address[] memory, uint256[] memory);

    function getOperatorStake(address operator, address collateral) external view returns (uint256);
}
