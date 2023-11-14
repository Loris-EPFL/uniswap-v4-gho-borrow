// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import {
    IPoolManager, Hooks, IHooks, BaseHook, BalanceDelta
} from "@uniswap-periphery/v4-periphery/contracts/BaseHook.sol";
import { IHookFeeManager } from "@uniswap/v4-core/contracts/interfaces/IHookFeeManager.sol";
import { IDynamicFeeManager } from "@uniswap/v4-core/contracts/interfaces/IDynamicFeeManager.sol";
import { console2 } from "forge-std/console2.sol";
import {IVariableDebtToken} from "@aave/core-v3/contracts/interfaces/IVariableDebtToken.sol";
import {ICreditDelegationToken} from "@aave/core-v3/contracts/interfaces/ICreditDelegationToken.sol";
import {IGhoVariableDebtToken} from '@aave/gho/facilitators/aave/tokens/interfaces/IGhoVariableDebtToken.sol';
import {GhoStableDebtToken} from '@aave/gho/facilitators/aave/tokens/GhoStableDebtToken.sol';
import {GhoVariableDebtToken} from '@aave/gho/facilitators/aave/tokens/GhoVariableDebtToken.sol';
import {IGhoToken} from '@aave/gho/gho/interfaces/IGhoToken.sol';
import {PoolKey} from "@uniswap/core-v4/contracts/types/PoolKey.sol";
import { PoolManager, Currency } from "@uniswap/v4-core/contracts/PoolManager.sol";
import { TickMath } from "@uniswap/v4-core/contracts/libraries/TickMath.sol";
import { Fees } from "@uniswap/v4-core/contracts/libraries/Fees.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/contracts/libraries/PoolId.sol";

contract BorrowHook is BaseHook, IHookFeeManager, IDynamicFeeManager {
    using PoolIdLibrary for IPoolManager.PoolKey;
    address public owner;

    uint8 maxLTV = 80; //80%
    address public ghoVariableDebtToken = 0x3FEaB6F8510C73E05b8C0Fdf96Df012E3A144319;

    address public gho = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f;
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    struct userLiquidity{
        uint256 liquidity;
        uint256 tickLower;
        uint256 tickUpper;
    }


    //max bucket capacity (= max total mintable gho capacity)
    uint128 public ghoBucketCapacity = 100000e18; //100k gho

    mapping(address => uint256) public userDebt;    //user debt
    mapping(address => uint256) public userCollateral; //user collateral

    mapping(address => bool) public isUserLiquidable; //flag to see if user is liquidable


    constructor(address _owner, IPoolManager _poolManager) BaseHook(_poolManager) {
        owner = _owner;
    }

    function getHooksCalls() public pure override returns (Hooks.Calls memory) {
        return Hooks.Calls({
            beforeInitialize: true,
            afterInitialize: true,
            beforeModifyPosition: true,
            afterModifyPosition: true,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: true,
            afterDonate: true
        });
    }

    /// @inheritdoc IHooks
    function beforeInitialize(
        address, // sender
        IPoolManager.PoolKey calldata, // key
        uint160 // sqrtPriceX96
    )
        external
        override
        returns (bytes4)
    {
        //replace with gho's variable debt token interface or stable debt ???
        /*ICreditDelegationToken(ghoVariableDebtToken).approveDelegation(
            debtHandler, 
            type(uint256).max
            ); //approve max gho debt to debtHandler contract
        */
        //adds the hook address as a gho faciliator, need permissions to do that (check IghoToken.sol)
        /*
        IGhoToken(gho).addFacilitator(
            address(this),
            "BorrowHook",
            ghoBucketCapacity);
        */
        console2.log("beforeInitialize");
        return IHooks.beforeInitialize.selector;
    }

    /// @inheritdoc IHooks
    function afterInitialize(
        address, // sender
        IPoolManager.PoolKey calldata, // key
        uint160, // sqrtPriceX96
        int24 // tick
    )
        external
        pure
        override
        returns (bytes4)
    {
        console2.log("afterInitialize");
        return IHooks.afterInitialize.selector;
    }

    /// @inheritdoc IHooks
    function beforeModifyPosition(
        address owner, // sender
        IPoolManager.PoolKey calldata, // key
        IPoolManager.ModifyPositionParams calldata // params
    )
        external
        override
        returns (bytes4)
    {
        console2.log("userLiquidity", _getUserLiquidityPriceUSD(owner));
        console2.log("beforeModifyPosition");
        return IHooks.beforeModifyPosition.selector;
    }

    /// @inheritdoc IHooks
    function afterModifyPosition(
        address owner, // sender
        IPoolManager.PoolKey calldata, // key
        IPoolManager.ModifyPositionParams calldata, // params
        BalanceDelta // delta
    )
        external
        override
        returns (bytes4)
    {
        console2.log("userLiquidity", _getUserLiquidityPriceUSD(owner));
        IGhoToken(gho).mint(owner, 1e18);
        console2.log("GHO balance", IGhoToken(gho).balanceOf(owner));
        console2.log("afterModifyPosition");
        return IHooks.afterModifyPosition.selector;
    }

    /// @inheritdoc IHooks
    function beforeSwap(
        address, // sender
        IPoolManager.PoolKey calldata, // key
        IPoolManager.SwapParams calldata // params
    )
        external
        pure
        override
        returns (bytes4)
    {
        console2.log("beforeSwap");
        return IHooks.beforeSwap.selector;
    }

    /// @inheritdoc IHooks
    function afterSwap(
        address, // sender
        IPoolManager.PoolKey calldata, // key
        IPoolManager.SwapParams calldata, // params
        BalanceDelta // delta
    )
        external
        pure
        override
        returns (bytes4)
    {
        console2.log("afterSwap");
        return IHooks.afterSwap.selector;
    }

    /// @inheritdoc IHooks
    function beforeDonate(
        address, // sender
        IPoolManager.PoolKey calldata, // key
        uint256, // amount0
        uint256 // amount1
    )
        external
        pure
        override
        returns (bytes4)
    {
        console2.log("beforeDonate");
        return IHooks.beforeDonate.selector;
    }

    /// @inheritdoc IHooks
    function afterDonate(
        address, // sender
        IPoolManager.PoolKey calldata, // key
        uint256, // amount0
        uint256 // amount1
    )
        external
        pure
        override
        returns (bytes4)
    {
        console2.log("afterDonate");
        return IHooks.afterDonate.selector;
    }

    /// @inheritdoc IHookFeeManager
    function getHookSwapFee(IPoolManager.PoolKey calldata) external pure returns (uint8) {
        console2.log("getHookSwapFee");
        return 100;
    }

    /// @inheritdoc IHookFeeManager
    function getHookWithdrawFee(IPoolManager.PoolKey calldata) external pure returns (uint8) {
        console2.log("getHookWithdrawFee");
        return 100;
    }

    /// @inheritdoc IDynamicFeeManager
    function getFee(IPoolManager.PoolKey calldata) external pure returns (uint24) {
        console2.log("getFee");
        return 10_000;
    }

    function borrowGho(uint256 amount, address user) public returns (bool, uint256){
        //borrow gho from ghoVariableDebtToken
        //TODO : implement logic to check if user has enough collateral to borrow
        if(_getUserLiquidityPriceUSD(user) >= ((amount+ userDebt[user])*maxLTV)/100){
            revert("user LTV is superior to maximum LTV"); //TODO add proper error message
        }
        userDebt[user] += amount;
        IGhoToken(gho).mint(user, amount);
        

        

        
    }

    function repayGho(uint256 amount, address user) public returns (bool, uint256){
        //repay gho to ghoVariableDebtToken
        //TODO : implement logic to check if user has enough gho to repay
        if(userDebt[user] < amount){
            revert("user debt is inferior to amount to repay");
        }
        IGhoToken(gho).burn(amount);
        userDebt[user] -= amount;
    }

    function _getUserLiquidityPriceUSD(address user) internal view returns (uint128){
        //get user liquidity
        IPoolManager.PoolKey memory key = _getPoolKey();
        int24 tickLower = TickMath.MIN_TICK;
        int24 tickUpper = TickMath.MAX_TICK;
        uint128 userLiquidity = poolManager.getLiquidity(key.toId(),user,  tickLower, tickUpper);
        console2.log("user liquidity", userLiquidity);
        return userLiquidity;
    }   


    //Helper function to return PoolKey
    function _getPoolKey() private view returns (IPoolManager.PoolKey memory) {
        return IPoolManager.PoolKey({
            currency0: Currency.wrap(address(WETH)),
            currency1: Currency.wrap(address(USDC)),
            fee: Fees.DYNAMIC_FEE_FLAG + Fees.HOOK_SWAP_FEE_FLAG + Fees.HOOK_WITHDRAW_FEE_FLAG, // 0xE00000 = 111
            tickSpacing: 1,
            hooks: IHooks(address(this))
        });
    }
}
