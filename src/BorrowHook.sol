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
import {SqrtPriceMath} from "@uniswap/v4-core/contracts/libraries/SqrtPriceMath.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {EACAggregatorProxy} from "./Interfaces/EACAggregatorProxy.sol";
import {UD60x18} from "@prb-math/UD60x18.sol";

contract BorrowHook is BaseHook, IHookFeeManager, IDynamicFeeManager {
    using PoolIdLibrary for IPoolManager.PoolKey;
    address public owner;

    uint8 maxLTV = 80; //80%
    address public ghoVariableDebtToken = 0x3FEaB6F8510C73E05b8C0Fdf96Df012E3A144319;

    address public gho = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f;
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    EACAggregatorProxy public ETHPriceFeed = EACAggregatorProxy(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    EACAggregatorProxy public USDCPriceFeed = EACAggregatorProxy(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);

    struct UserLiquidity{
        uint128 liquidity;
        int24 tickLower;
        int24 tickUpper;
    }


    //max bucket capacity (= max total mintable gho capacity)
    uint128 public ghoBucketCapacity = 100000e18; //100k gho

    mapping(address => uint256) public userDebt;    //user debt
    mapping(address => UserLiquidity) public userPosition; //user collateral

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
        IPoolManager.ModifyPositionParams calldata params// params
    )
        external
        override
        returns (bytes4)
    {
        
        console2.log("beforeModifyPosition");
        return IHooks.beforeModifyPosition.selector;
    }

    /// @inheritdoc IHooks
    function afterModifyPosition(
        address owner, // sender
        IPoolManager.PoolKey calldata, // key
        IPoolManager.ModifyPositionParams calldata params, // params
        BalanceDelta // delta
    )
        external
        override
        returns (bytes4)
    {

        _storeUserPosition(owner, params);
        //_getUserLiquidityPriceUSD(owner);
        console2.log("userPosition in usd %e", _getUserLiquidityPriceUSD(owner).unwrap());
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
        address sender, // sender
        IPoolManager.PoolKey calldata, // key
        IPoolManager.SwapParams calldata, // params
        BalanceDelta // delta
    )
        external
        override
        returns (bytes4)
    {
        console2.log("afterSwap");
        console2.log("user position price in USD after swap %e", _getUserLiquidityPriceUSD(sender).unwrap() / 10**18);
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
        if(amount < 1e18){
            revert("amount to borrow is inferior to 1 GHO");
        }
        //TODO : implement logic to check if user has enough collateral to borrow
        console2.log("user price position before borrowing %e", _getUserLiquidityPriceUSD(user).unwrap() / 10**18);
        console2.log("amount requested %e", amount);    
        console2.log("Max borrow amount %e", _getUserLiquidityPriceUSD(user).sub((UD60x18.wrap(userDebt[user])).div(UD60x18.wrap(10**ERC20(gho).decimals()))).mul(UD60x18.wrap(maxLTV)).div(UD60x18.wrap(100)).unwrap());
        //get user position price in USD, then check if borrow amount + debt already owed (adjusted to gho decimals) is inferior to maxLTV (80% = maxLTV/100)
        if(_getUserLiquidityPriceUSD(user).lte((UD60x18.wrap((amount+ userDebt[user])).div(UD60x18.wrap(10**ERC20(gho).decimals()))).mul(UD60x18.wrap(maxLTV)).div(UD60x18.wrap(100)))){ 
            revert("user LTV is superior to maximum LTV"); //TODO add proper error message
        }
        userDebt[user] += amount;
        IGhoToken(gho).mint(user, amount);
    
    }

    function viewGhoDebt(address user) public view returns (uint256){
        return userDebt[user];
    }

    function repayGho(uint256 amount, address user) public returns (bool, uint256){
        //repay gho to ghoVariableDebtToken
        //TODO : implement logic to check if user has enough gho to repay
        if(userDebt[user] < amount){
            revert("user debt is inferior to amount to repay");
        }
        bool isSuccess = ERC20(gho).transferFrom(user, address(this), amount); //send gho to this address then burning it
        if(!isSuccess){
            revert("transferFrom failed");
        }else{
            IGhoToken(gho).burn(amount);
            userDebt[user] -= amount;
        }
        
    }

    function _getUserLiquidityPriceUSD(address user) internal view returns (UD60x18){
        
        IPoolManager.PoolKey memory key = _getPoolKey();
        (uint160 sqrtPriceX96, int24 currentTick, , , , ) = poolManager.getSlot0(key.toId()); //curent price and tick of the pool
        UserLiquidity memory userCurrentPosition = userPosition[user];
        

        uint160 sqrtPriceLower = TickMath.getSqrtRatioAtTick(userCurrentPosition.tickLower); //get price as decimal from Q64.96 format
        uint160 sqrtPriceUpper = TickMath.getSqrtRatioAtTick(userCurrentPosition.tickUpper);
        uint256 token0amount;
        uint256 token1amount;


        //Price calculations on https://blog.uniswap.org/uniswap-v3-math-primer-2#how-to-calculate-current-holdings
        //Out of range, on the downside
        if(currentTick < userCurrentPosition.tickLower){
            token0amount = SqrtPriceMath.getAmount0Delta(
                sqrtPriceLower,
                sqrtPriceUpper,
                userCurrentPosition.liquidity,
                false
            );
            token1amount = 0;
        //Out of range, on the upside
        }else if(currentTick >= userCurrentPosition.tickUpper){
            token0amount = 0;
            token1amount = SqrtPriceMath.getAmount1Delta(
                sqrtPriceLower,
                sqrtPriceUpper,
                userCurrentPosition.liquidity,
                false
            );
        //in range position
        }else{
            token0amount = SqrtPriceMath.getAmount0Delta(
                sqrtPriceX96,
                sqrtPriceUpper,
                userCurrentPosition.liquidity,
                false
            );
            token1amount = SqrtPriceMath.getAmount1Delta(
                sqrtPriceLower,
                sqrtPriceX96,
                userCurrentPosition.liquidity,
                false
            );
        }
        /*
        console2.log("token0 amount from ERC20 %e", ERC20(Currency.unwrap(key.currency0)).balanceOf(address(poolManager)));
        console2.log("token1 amount from ERC20 %e", ERC20(Currency.unwrap(key.currency1)).balanceOf(address(poolManager)));



        console2.log("token0 amount %e", token0amount / 10**ERC20(Currency.unwrap(key.currency0)).decimals());
        console2.log("token1 amount %e", token1amount / 10**ERC20(Currency.unwrap(key.currency1)).decimals());
        */

       

        //Use UD60x18 to convert token amount to decimal adjusted to avoid overflow errors
        UD60x18 token0amountUD60x18 = UD60x18.wrap(token0amount).div(UD60x18.wrap(10**ERC20(Currency.unwrap(key.currency0)).decimals()));
        UD60x18 token1amountUD60x18 = UD60x18.wrap(token1amount).div(UD60x18.wrap(10**ERC20(Currency.unwrap(key.currency1)).decimals()));

        /*
        console2.log("token0 amount UD60x18 %e", token0amountUD60x18.unwrap());
        console2.log("token0 amount UD60x18 %e", token1amountUD60x18.unwrap());
        */


       
        //Price feed from Chainlink, convert to UD60x18 to avoid overflow errors

        /*
        console2.log("ETH price %e", uint256(ETHPriceFeed.latestAnswer()) / 10**ETHPriceFeed.decimals());
        //console2.log("with %e decimals", ETHPriceFeed.decimals());
        console2.log("USDC price %e", uint256(USDCPriceFeed.latestAnswer()) / 10**USDCPriceFeed.decimals());
        //console2.log("with %e decimals", USDCPriceFeed.decimals());
        */
        UD60x18 ETHPrice = UD60x18.wrap(uint256(ETHPriceFeed.latestAnswer())).div(UD60x18.wrap(10**ETHPriceFeed.decimals()));
        UD60x18 USDCPrice = UD60x18.wrap(uint256(USDCPriceFeed.latestAnswer())).div(UD60x18.wrap(10**USDCPriceFeed.decimals()));

        /*
        console2.log("ETH price UDx60 %e", ETHPrice.unwrap());
        console2.log("USDC price UDx60 %e", USDCPrice.unwrap());
        */
       

        //Price value of each token in the position
        UD60x18 token0Price = token0amountUD60x18.mul(ETHPrice);
        UD60x18 token1Price = token1amountUD60x18.mul(USDCPrice);

        
        /*
        //Amount of token0 and token1 in the position
        console2.log("token0 in UD60 %e", UD60x18.unwrap(token0amountUD60x18));
        console2.log("token1 in UD60 %e", UD60x18.unwrap(token1amountUD60x18));
        */

       
        //Price value of the position
        console2.log("position price %e", (token0Price.add(token1Price)).unwrap()/(10**18));


        //return price value of the position as UD60x18
        return token0Price.add(token1Price);
    }   

    function _storeUserPosition(address user, IPoolManager.ModifyPositionParams calldata params) internal{
        //get user liquidity
        int24 tickLower = params.tickLower;
        int24 tickUpper = params.tickUpper;

        IPoolManager.PoolKey memory key = _getPoolKey();
        (uint160 sqrtPriceX96, int24 currentTick, , , , ) = poolManager.getSlot0(key.toId());
        uint128 userLiquidity = poolManager.getLiquidity(key.toId(),user,  tickLower, tickUpper);

        userPosition[user] = UserLiquidity(
            userLiquidity,
            tickLower,
            tickUpper
        );

        console2.log("user liquidity", userLiquidity);
        console2.log("user tick lower", tickLower);
        console2.log("user tick upper", tickUpper);

    }


    //Helper function to return PoolKey
    function _getPoolKey() private view returns (IPoolManager.PoolKey memory) {
        return IPoolManager.PoolKey({
            currency0: Currency.wrap(address(WETH)),
            currency1: Currency.wrap(address(USDC)),
            fee: Fees.DYNAMIC_FEE_FLAG + Fees.HOOK_SWAP_FEE_FLAG + Fees.HOOK_WITHDRAW_FEE_FLAG, // 0xE00000 = 111
            tickSpacing: 60,
            hooks: IHooks(address(this))
        });
    }
}
