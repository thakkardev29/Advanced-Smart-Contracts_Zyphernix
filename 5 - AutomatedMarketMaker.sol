// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title AutomatedMarketMaker
 * @notice Simple constant-product AMM with LP token issuance
 */
contract AutomatedMarketMaker is ERC20 {

    IERC20 public immutable assetA;
    IERC20 public immutable assetB;

    uint256 private reserveA;
    uint256 private reserveB;

    address public immutable owner;

    /* ========== EVENTS ========== */

    event LiquidityProvided(
        address indexed provider,
        uint256 amountA,
        uint256 amountB,
        uint256 lpTokensMinted
    );

    event LiquidityWithdrawn(
        address indexed provider,
        uint256 amountA,
        uint256 amountB,
        uint256 lpTokensBurned
    );

    event SwapExecuted(
        address indexed user,
        address indexed tokenIn,
        uint256 amountIn,
        address indexed tokenOut,
        uint256 amountOut
    );

    constructor(
        address _tokenA,
        address _tokenB,
        string memory _lpName,
        string memory _lpSymbol
    ) ERC20(_lpName, _lpSymbol) {
        assetA = IERC20(_tokenA);
        assetB = IERC20(_tokenB);
        owner = msg.sender;
    }

    /* ========== LIQUIDITY MANAGEMENT ========== */

    function addLiquidity(uint256 amountA, uint256 amountB) external {
        require(amountA > 0 && amountB > 0, "Invalid liquidity amounts");

        assetA.transferFrom(msg.sender, address(this), amountA);
        assetB.transferFrom(msg.sender, address(this), amountB);

        uint256 liquidityMinted;

        if (totalSupply() == 0) {
            liquidityMinted = _sqrt(amountA * amountB);
        } else {
            liquidityMinted = _min(
                (amountA * totalSupply()) / reserveA,
                (amountB * totalSupply()) / reserveB
            );
        }

        _mint(msg.sender, liquidityMinted);

        reserveA += amountA;
        reserveB += amountB;

        emit LiquidityProvided(msg.sender, amountA, amountB, liquidityMinted);
    }

    function removeLiquidity(uint256 lpAmount)
        external
        returns (uint256 amountAOut, uint256 amountBOut)
    {
        require(lpAmount > 0, "LP amount must be positive");
        require(balanceOf(msg.sender) >= lpAmount, "Not enough LP tokens");

        uint256 totalLP = totalSupply();
        require(totalLP > 0, "Pool is empty");

        amountAOut = (lpAmount * reserveA) / totalLP;
        amountBOut = (lpAmount * reserveB) / totalLP;

        require(amountAOut > 0 && amountBOut > 0, "Insufficient pool reserves");

        reserveA -= amountAOut;
        reserveB -= amountBOut;

        _burn(msg.sender, lpAmount);

        assetA.transfer(msg.sender, amountAOut);
        assetB.transfer(msg.sender, amountBOut);

        emit LiquidityWithdrawn(msg.sender, amountAOut, amountBOut, lpAmount);
    }

    /* ========== SWAP LOGIC ========== */

    function swapAForB(uint256 amountIn, uint256 minOut) external {
        require(amountIn > 0, "Invalid input amount");
        require(reserveA > 0 && reserveB > 0, "Empty pool");

        uint256 adjustedInput = (amountIn * 997) / 1000;
        uint256 outputAmount =
            (reserveB * adjustedInput) / (reserveA + adjustedInput);

        require(outputAmount >= minOut, "Slippage exceeded");

        assetA.transferFrom(msg.sender, address(this), amountIn);
        assetB.transfer(msg.sender, outputAmount);

        reserveA += adjustedInput;
        reserveB -= outputAmount;

        emit SwapExecuted(
            msg.sender,
            address(assetA),
            amountIn,
            address(assetB),
            outputAmount
        );
    }

    function swapBForA(uint256 amountIn, uint256 minOut) external {
        require(amountIn > 0, "Invalid input amount");
        require(reserveA > 0 && reserveB > 0, "Empty pool");

        uint256 adjustedInput = (amountIn * 997) / 1000;
        uint256 outputAmount =
            (reserveA * adjustedInput) / (reserveB + adjustedInput);

        require(outputAmount >= minOut, "Slippage exceeded");

        assetB.transferFrom(msg.sender, address(this), amountIn);
        assetA.transfer(msg.sender, outputAmount);

        reserveB += adjustedInput;
        reserveA -= outputAmount;

        emit SwapExecuted(
            msg.sender,
            address(assetB),
            amountIn,
            address(assetA),
            outputAmount
        );
    }

    /* ========== VIEW FUNCTIONS ========== */

    function getReserves()
        external
        view
        returns (uint256, uint256)
    {
        return (reserveA, reserveB);
    }

    /* ========== INTERNAL UTILITIES ========== */

    function _min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x < y ? x : y;
    }

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
}
