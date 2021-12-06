// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.7.5;

import "../libs/SafeMath.sol";
import "../libs/FixedPoint.sol";
import "../libs/Address.sol";
import "../libs/SafeERC20.sol";

import "../interfaces/IERC20Metadata.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IBondingCalculator.sol";
import "../interfaces/IUniswapV2ERC20.sol";
import "../interfaces/IUniswapV2Pair.sol";

contract SphynxBondingCalculator is IBondingCalculator {
    using FixedPoint for *;
    using SafeMath for uint256;

    IERC20 internal immutable SPH;

    constructor(address _SPH) {
        require(_SPH != address(0), "Zero address: SPH");
        SPH = IERC20(_SPH);
    }

    function getKValue(address _pair) public view returns (uint256 k_) {
        uint256 token0 = IERC20Metadata(IUniswapV2Pair(_pair).token0()).decimals();
        uint256 token1 = IERC20Metadata(IUniswapV2Pair(_pair).token1()).decimals();
        uint256 decimals = token0.add(token1).sub(IERC20Metadata(_pair).decimals());

        (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(_pair).getReserves();
        k_ = reserve0.mul(reserve1).div(10**decimals);
    }

    function getTotalValue(address _pair) public view returns (uint256 _value) {
        _value = getKValue(_pair).sqrrt().mul(2);
    }

    function valuation(address _pair, uint256 amount_) external view override returns (uint256 _value) {
        uint256 totalValue = getTotalValue(_pair);
        uint256 totalSupply = IUniswapV2Pair(_pair).totalSupply();

        _value = totalValue.mul(FixedPoint.fraction(amount_, totalSupply).decode112with18()).div(1e18);
    }

    function markdown(address _pair) external view override returns (uint256) {
        (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(_pair).getReserves();

        uint256 reserve;
        if (IUniswapV2Pair(_pair).token0() == address(SPH)) {
            reserve = reserve1;
        } else {
            require(IUniswapV2Pair(_pair).token1() == address(SPH), "Invalid pair");
            reserve = reserve0;
        }
        return reserve.mul(2 * (10**IERC20Metadata(address(SPH)).decimals())).div(getTotalValue(_pair));
    }
}
