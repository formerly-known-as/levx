// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

interface IComptroller {
    function enterMarkets(address[] memory cTokens) external;
}
