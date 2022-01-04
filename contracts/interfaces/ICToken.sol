// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

interface ICToken {
    function borrow(uint256) external returns (uint256);

    function mint(uint256) external returns (uint256);

    function redeem(uint256) external returns (uint256);

    function redeemUnderlying(uint256) external returns (uint256);

    function repayBorrow(uint256) external returns (uint256);

    function underlying() external view returns (address);
}
