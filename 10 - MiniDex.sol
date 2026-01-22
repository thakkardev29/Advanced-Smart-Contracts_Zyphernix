// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract MiniDexPair is ReentrancyGuard {

    address public immutable asset0;
    address public immutable asset1;

    uint256 private reserve0;
    uint256 private reserve1;
    uint256 private lpTotalSupply;

    mapping(address => uint256) private lpBalanceOf;

    /* ========== EVENTS ========== */

    event LiquidityAdded(
        address indexed provider,
        uint256 amount0,
        uint256 amount1,
        uint256 lpMinted
    );

    event LiquidityRemoved(
        address indexed provider,
        uint256 amount0,
        uint256 amount1,
        uint256 lpBurned
    );

    event SwapExecuted(
        address indexed trader,
        address indexed tokenIn,
        uint256 amountIn,
        address indexed tokenOut,
        uint256 amountOut
    );

    constructor(address _asset0, address _asset1) {
        require(_asset0 != _asset1, "Tokens must differ");
        require(_asset0 != address(0) && _asset1 != address(0), "Zero address");

        asset0 = _asset0;
        asset1 = _asset1;
    }

    /* ========== INTERNAL UTILITIES ========== */

    function _sqrt(uint256 value) internal pure returns (uint256 result) {
        if (value > 3) {
            result = value;
            uint256 temp = (value / 2) + 1;
            while (temp < result) {
                result = temp;
                temp = (value / temp + temp) / 2;
            }
        } else if (value != 0) {
            result = 1;
        }
    }

    function _min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x < y ? x : y;
    }

    function _syncReserves() internal {
        reserve0 = IERC20(asset0).balanceOf(address(this));
        reserve1 = IERC20(asset1).balanceOf(address(this));
    }

    /* ========== LIQUIDITY LOGIC ========== */

    function addLiquidity(uint256 amount0, uint256 amount1)
        external
        nonReentrant
    {
        require(amount0 > 0 && amount1 > 0, "Invalid liquidity amounts");

        IERC20(asset0).transferFrom(msg.sender, address(this), amount0);
        IERC20(asset1).transferFrom(msg.sender, address(this), amount1);

        uint256 lpMinted;

        if (lpTotalSupply == 0) {
            lpMinted = _sqrt(amount0 * amount1);
        } else {
            lpMinted = _min(
                (amount0 * lpTotalSupply) / reserve0,
                (amount1 * lpTotalSupply) / reserve1
            );
        }

        require(lpMinted > 0, "LP mint failed");

        lpBalanceOf[msg.sender] += lpMinted;
        lpTotalSupply += lpMinted;

        _syncReserves();

        emit LiquidityAdded(
            msg.sender,
            amount0,
            amount1,
            lpMinted
        );
    }

    function removeLiquidity(uint256 lpAmount)
        external
        nonReentrant
    {
        require(
            lpAmount > 0 && lpAmount <= lpBalanceOf[msg.sender],
            "Invalid LP amount"
        );

        uint256 amount0 =
            (lpAmount * reserve0) / lpTotalSupply;

        uint256 amount1 =
            (lpAmount * reserve1) / lpTotalSupply;

        lpBalanceOf[msg.sender] -= lpAmount;
        lpTotalSupply -= lpAmount;

        IERC20(asset0).transfer(msg.sender, amount0);
        IERC20(asset1).transfer(msg.sender, amount1);

        _syncReserves();

        emit LiquidityRemoved(
            msg.sender,
            amount0,
            amount1,
            lpAmount
        );
    }

    /* ========== SWAP LOGIC ========== */

    function quoteSwap(uint256 amountIn, address tokenIn)
        public
        view
        returns (uint256 amountOut)
    {
        require(
            tokenIn == asset0 || tokenIn == asset1,
            "Unsupported token"
        );

        bool zeroToOne = tokenIn == asset0;

        (uint256 reserveIn, uint256 reserveOut) =
            zeroToOne
                ? (reserve0, reserve1)
                : (reserve1, reserve0);

        uint256 amountWithFee = amountIn * 997;
        uint256 numerator = amountWithFee * reserveOut;
        uint256 denominator =
            (reserveIn * 1000) + amountWithFee;

        amountOut = numerator / denominator;
    }

    function swap(uint256 amountIn, address tokenIn)
        external
        nonReentrant
    {
        require(amountIn > 0, "Zero input");
        require(
            tokenIn == asset0 || tokenIn == asset1,
            "Invalid token"
        );

        address tokenOut =
            tokenIn == asset0 ? asset1 : asset0;

        uint256 amountOut = quoteSwap(amountIn, tokenIn);
        require(amountOut > 0, "Zero output");

        IERC20(tokenIn).transferFrom(
            msg.sender,
            address(this),
            amountIn
        );

        IERC20(tokenOut).transfer(
            msg.sender,
            amountOut
        );

        _syncReserves();

        emit SwapExecuted(
            msg.sender,
            tokenIn,
            amountIn,
            tokenOut,
            amountOut
        );
    }

    /* ========== VIEW FUNCTIONS ========== */

    function getReserves()
        external
        view
        returns (uint256, uint256)
    {
        return (reserve0, reserve1);
    }

    function lpBalance(address user)
        external
        view
        returns (uint256)
    {
        return lpBalanceOf[user];
    }

    function totalLiquidity()
        external
        view
        returns (uint256)
    {
        return lpTotalSupply;
    }
}
