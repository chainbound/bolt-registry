// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IWETH {
    function approve(address guy, uint256 wad) external;
    function transferFrom(address src, address dst, uint256 wad) external;
    function withdraw(
        uint256 wad
    ) external;
    function transfer(address dst, uint256 wad) external returns (bool);
    function deposit() external payable;
}
