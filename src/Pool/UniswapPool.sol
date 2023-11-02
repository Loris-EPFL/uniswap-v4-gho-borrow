// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {BaseHook} from "@uniswap-periphery/v4-periphery/contracts/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/contracts/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/contracts/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/contracts/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "forge-std/console.sol";
error SwapExpired();
error OnlyPoolManager();

using CurrencyLibrary for Currency;
using SafeERC20 for IERC20;

contract UniswapPool {
    struct LiquidityRange {
        int24 tickLower; // The lower tick of the range
        int24 tickUpper; // The upper tick of the range
    }
    mapping(address => LiquidityRange) public liquidityRanges;
    IPoolManager public poolManager;

    // Token addresses
    address public tokenA;
    address public tokenB;

    // Mapping to track liquidity token balances for each provider
    mapping(address => uint256) public liquidityBalances;

    event LiquidityDeposited(address indexed provider, uint256 amount);
    event LiquidityWithdrawn(address indexed provider, uint256 amount);

    constructor(IPoolManager _poolManager, address tokenA_, address tokenB_) {
        poolManager = _poolManager;
        poolManager.beforeInitialize(
           //do the logic with credit delegation in here (delegate credit to a creditHandler contract)
            );
            
        tokenA = tokenA_;
        tokenB = tokenB_;
    }

    function swapTokens(
        PoolKey calldata poolKey,
        IPoolManager.SwapParams calldata swapParams,
        uint256 deadline
    ) public payable {
        poolManager.lock(abi.encode(poolKey, swapParams, deadline));
    }

    // Function to deposit liquidity
    function depositLiquidity(
        uint256 amountTokenA,
        uint256 amountTokenB,
        int24 tickLower,
        int24 tickUpper
    ) external {
        // Transfer the tokens from the provider to the contract
        IERC20(tokenA).safeTransferFrom(
            msg.sender,
            address(this),
            amountTokenA
        );
        IERC20(tokenB).safeTransferFrom(
            msg.sender,
            address(this),
            amountTokenB
        );

        // Calculate liquidity tokens to mint (this is a simplified example, actual calculation might be different)
        uint256 liquidityTokens = amountTokenA + amountTokenB; // Simplified for demonstration

        // Update the liquidity balance for the provider
        liquidityBalances[msg.sender] += liquidityTokens;

        liquidityRanges[msg.sender] = LiquidityRange(tickLower, tickUpper);

        emit LiquidityDeposited(msg.sender, liquidityTokens);
    }

    // Function to withdraw liquidity
    function withdrawLiquidity(
        address user,
        uint256 liquidityTokens
    ) external returns (uint256 amountTokenA, uint256 amountTokenB) {
        require(
            liquidityBalances[user] >= liquidityTokens,
            "Not enough liquidity tokens"
        );

        // Burn the liquidity tokens from the provider's balance
        liquidityBalances[user] -= liquidityTokens;

        // Calculate the amount of each token to return (this is a simplified example, actual calculation might be different)
        amountTokenA = liquidityTokens / 2; // Simplified for demonstration
        amountTokenB = liquidityTokens / 2; // Simplified for demonstration

        // Transfer the tokens back to the provider
        IERC20(tokenA).safeTransfer(msg.sender, amountTokenA);
        IERC20(tokenB).safeTransfer(msg.sender, amountTokenB);

        emit LiquidityWithdrawn(user, liquidityTokens);
    }

    function lockAcquired(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) {
            revert OnlyPoolManager();
        }

        (
            PoolKey memory poolKey,
            IPoolManager.SwapParams memory swapParams,
            uint256 deadline
        ) = abi.decode(data, (PoolKey, IPoolManager.SwapParams, uint256));

        if (block.timestamp > deadline) {
            revert SwapExpired();
        }

        BalanceDelta delta = poolManager.swap(
            poolKey,
            swapParams,
            new bytes(0)
        );

        _settleCurrencyBalance(poolKey.currency0, delta.amount0());
        _settleCurrencyBalance(poolKey.currency1, delta.amount1());

        return new bytes(0);
    }

    function _settleCurrencyBalance(
        Currency currency,
        int128 deltaAmount
    ) private {
        if (deltaAmount < 0) {
            poolManager.take(currency, msg.sender, uint128(-deltaAmount));
            return;
        }

        if (currency.isNative()) {
            poolManager.settle{value: uint128(deltaAmount)}(currency);
            return;
        }

        IERC20(Currency.unwrap(currency)).safeTransferFrom(
            msg.sender,
            address(poolManager),
            uint128(deltaAmount)
        );
        poolManager.settle(currency);
    }
}
