// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./LevX.sol";

contract LevXFactory {
    address public immutable comptroller;
    address public immutable sushiFactory;
    address public immutable weth;

    mapping(address => LevX[]) public userLevX;

    constructor(
        address _comptroller,
        address _sushiFactory,
        address _weth
    ) {
        comptroller = _comptroller;
        sushiFactory = _sushiFactory;
        weth = _weth;
    }

    function create() external returns (LevX) {
        LevX levX = new LevX(msg.sender, comptroller, sushiFactory, weth);
        userLevX[msg.sender].push(levX);
        return levX;
    }
}
