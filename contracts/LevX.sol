// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IComptroller.sol";
import "./interfaces/ICToken.sol";
import "./interfaces/ISushiSwap.sol";
import "./libraries/SushiUtils.sol";

contract LevX is Ownable, SushiUtils {
    using SafeERC20 for IERC20;

    address public immutable comptroller;
    address public immutable sushiFactory;
    address public immutable weth;

    constructor(
        address _user,
        address _comptroller,
        address _sushiFactory,
        address _weth
    ) {
        comptroller = _comptroller;
        sushiFactory = _sushiFactory;
        weth = _weth;
        transferOwnership(_user);
    }

    function withdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }

    function open(
        address cylong,
        address long,
        uint256 lamt,
        address cyshort,
        address short,
        uint256 samt,
        address cymargin,
        uint256 mamt
    ) external onlyOwner {
        address[] memory _markets = new address[](2);
        _markets[0] = cylong;
        _markets[1] = cymargin;
        IComptroller(comptroller).enterMarkets(_markets);
        IERC20(cymargin).safeTransferFrom(owner(), address(this), mamt);
        _borrow(cylong, long, lamt, cyshort, short, samt);
    }

    function close(
        address cyrepay,
        address repay,
        uint256 ramt,
        address cywithdraw,
        address uwithdraw,
        uint256 wamt
    ) external onlyOwner {
        address tokenB = repay == weth ? uwithdraw : weth;
        address _pairFrom = _pairFor(sushiFactory, repay, tokenB);
        (uint256 amount0, uint256 amount1) = repay < tokenB
            ? (ramt, uint256(0))
            : (uint256(0), ramt);
        ISushiSwap(_pairFrom).swap(
            amount0,
            amount1,
            address(this),
            abi.encode(
                cyrepay,
                repay,
                ramt,
                _pairFrom,
                cywithdraw,
                uwithdraw,
                wamt,
                false
            )
        );
    }

    function _borrow(
        address cylong,
        address long,
        uint256 lamt,
        address cyshort,
        address short,
        uint256 samt
    ) internal {
        (uint256 amount0, uint256 amount1) = long < weth
            ? (lamt, uint256(0))
            : (uint256(0), lamt);
        address tokenB = long == weth ? short : weth;
        address _pairFrom = _pairFor(sushiFactory, long, tokenB);
        ISushiSwap(_pairFrom).swap(
            amount0,
            amount1,
            address(this),
            abi.encode(
                cylong,
                long,
                lamt,
                _pairFrom,
                cyshort,
                short,
                samt,
                true
            )
        );
    }

    function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external {
        require(sender == address(this), "untrusted sender");
        (
            address _cylong,
            address _long,
            uint256 _lamt,
            address _pairFrom,
            address _cyshort,
            address _short,
            uint256 _samt,
            bool _pos
        ) = abi.decode(
                data,
                (
                    address,
                    address,
                    uint256,
                    address,
                    address,
                    address,
                    uint256,
                    bool
                )
            );
        {
            address tokenB = _long == weth ? _short : weth;
            require(
                msg.sender == _pairFor(sushiFactory, _long, tokenB),
                "untrusted caller"
            );
        }
        if (_pos) {
            _open(
                _cylong,
                _lamt,
                _pairFrom,
                amount0,
                _short,
                _long,
                _samt,
                _cyshort
            );
        } else {
            _close(
                _cylong,
                _lamt,
                _pairFrom,
                amount0,
                _short,
                _long,
                _samt,
                _cyshort
            );
        }
    }

    function _close(
        address _cyrepay,
        uint256 _ramt,
        address _pairFrom,
        uint256 _amount0,
        address _withdraw,
        address _repay,
        uint256 _wamt,
        address _cywithdraw
    ) internal {
        // TODO: Reset allowance check
        IERC20(_withdraw).safeIncreaseAllowance(_cyrepay, _ramt);
        require(ICToken(_cyrepay).repayBorrow(_ramt) == 0, "failed to repay");

        (uint256 reserve0, uint256 reserve1, ) = ISushiSwap(_pairFrom)
            .getReserves();
        (uint256 reserveIn, uint256 reserveOut) = _amount0 > 0
            ? (reserve1, reserve0)
            : (reserve0, reserve1);

        uint256 _minRepay = _getAmountIn(_ramt, reserveIn, reserveOut);

        if (_withdraw == weth || _repay == weth) {
            require(_minRepay <= _wamt, "incorrect amount");
            require(
                ICToken(_cywithdraw).redeemUnderlying(_minRepay) == 0,
                "failed to redeem"
            );
            IERC20(_withdraw).safeTransfer(address(_pairFrom), _minRepay);
        } else {
            _crossClose(
                _withdraw,
                _minRepay,
                _wamt,
                _cywithdraw,
                address(_pairFrom)
            );
        }
    }

    function _open(
        address _cylong,
        uint256 _lamt,
        address _pairFrom,
        uint256 _amount0,
        address _short,
        address _long,
        uint256 _samt,
        address _cyshort
    ) internal {
        // TODO: Reset allowance check
        IERC20(_long).safeIncreaseAllowance(_cylong, _lamt);
        require(ICToken(_cylong).mint(_lamt) == 0, "failed to mint");

        (uint256 reserve0, uint256 reserve1, ) = ISushiSwap(_pairFrom)
            .getReserves();
        (uint256 reserveIn, uint256 reserveOut) = _amount0 > 0
            ? (reserve1, reserve0)
            : (reserve0, reserve1);

        uint256 _minRepay = _getAmountIn(_lamt, reserveIn, reserveOut);

        if (_short == weth || _long == weth) {
            require(_minRepay <= _samt, "incorrect amount");
            require(
                ICToken(_cyshort).borrow(_minRepay) == 0,
                "failed to borrow"
            );
            IERC20(_short).safeTransfer(address(_pairFrom), _minRepay);
        } else {
            _cross(_short, _minRepay, _samt, _cyshort, address(_pairFrom));
        }
    }

    function _getShortFall(
        address _short,
        ISushiSwap _pairTo,
        uint256 _minWETHRepay
    ) internal view returns (address, uint256) {
        (address token0, ) = _short < weth ? (_short, weth) : (weth, _short);
        (uint256 reserve0, uint256 reserve1, ) = _pairTo.getReserves();
        (uint256 reserveIn, uint256 reserveOut) = token0 == _short
            ? (reserve0, reserve1)
            : (reserve1, reserve0);
        return (token0, _getAmountIn(_minWETHRepay, reserveIn, reserveOut));
    }

    function _cross(
        address _short,
        uint256 _minWETHRepay,
        uint256 _samt,
        address _cyshort,
        address _pairFrom
    ) internal {
        ISushiSwap _pairTo = ISushiSwap(_pairFor(sushiFactory, _short, weth));
        (address token0, uint256 _shortPay) = _getShortFall(
            _short,
            _pairTo,
            _minWETHRepay
        );
        require(_shortPay <= _samt, "incorrect amount");
        require(ICToken(_cyshort).borrow(_shortPay) == 0, "failed to borrow");
        (uint256 amount0, uint256 amount1) = token0 == _short
            ? (uint256(0), _minWETHRepay)
            : (_minWETHRepay, uint256(0));
        IERC20(_short).safeTransfer(address(_pairTo), _shortPay);
        _pairTo.swap(amount0, amount1, _pairFrom, new bytes(0));
    }

    function _crossClose(
        address _withdraw,
        uint256 _minWETHRepay,
        uint256 _wamt,
        address _cywithdraw,
        address _pairFrom
    ) internal {
        ISushiSwap _pairTo = ISushiSwap(
            _pairFor(sushiFactory, _withdraw, weth)
        );
        (address token0, uint256 _shortPay) = _getShortFall(
            _withdraw,
            _pairTo,
            _minWETHRepay
        );
        require(_shortPay <= _wamt, "incorrect amount");
        require(
            ICToken(_cywithdraw).redeemUnderlying(_shortPay) == 0,
            "failed to redeem"
        );
        (uint256 amount0, uint256 amount1) = token0 == _withdraw
            ? (uint256(0), _minWETHRepay)
            : (_minWETHRepay, uint256(0));
        IERC20(_withdraw).safeTransfer(address(_pairTo), _shortPay);
        _pairTo.swap(amount0, amount1, _pairFrom, new bytes(0));
    }
}
