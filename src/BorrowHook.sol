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
import {IterableMapping} from "./utils/IterableMapping.sol";

contract BorrowHook is BaseHook, IHookFeeManager, IDynamicFeeManager {
    using PoolIdLibrary for IPoolManager.PoolKey;
    using IterableMapping for IterableMapping.Map;

    address public owner;

    uint8 maxLTV = 80; //80%

    UD60x18 maxLTVUD60x18 = UD60x18.wrap(maxLTV).div(UD60x18.wrap(100));
    uint256 minBorrowAmount = 1e18; //1 GHO
    address public gho = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f;
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    EACAggregatorProxy public ETHPriceFeed = EACAggregatorProxy(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419); //chainlink ETH price feed
    EACAggregatorProxy public USDCPriceFeed = EACAggregatorProxy(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6); //chainlink USDC price feed

    struct UserLiquidity{
        uint128 liquidity;
        int24 tickLower;
        int24 tickUpper;
    }


    //max bucket capacity (= max total mintable gho capacity)
    uint128 public ghoBucketCapacity = 100000e18; //100k gho

    IterableMapping.Map private usersDebt; //users
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
        view
        returns (bytes4)
    {

        console2.log("beforeModifyPosition");

        if(params.liquidityDelta < 0 ){
            //If user try to withdraw (delta negative) and has debt, revert
            uint256 liquidity = uint256(-params.liquidityDelta);
            console2.log("liquidity to withdraw %e", uint128(liquidity));
            console2.log("can withdraw ? ", _canUserWithdraw(owner, params.tickLower, params.tickUpper, uint128(liquidity)));
            if(!_canUserWithdraw(owner, params.tickLower, params.tickUpper, uint128(liquidity))){
                 revert("user has debt, cannot withdraw"); //todo allow partial withdraw according to debt
            }
        }
        
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
        console2.log("userPosition in usd %e", _getUserLiquidityPriceUSD(owner).unwrap() / 10**18);
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
        //if amount is inferior to min amount, revert
        if(amount < minBorrowAmount){
            revert("amount to borrow is inferior to 1 GHO");
        }
        //TODO : implement logic to check if user has enough collateral to borrow
        console2.log("user price position before borrowing %e", _getUserLiquidityPriceUSD(user).unwrap() / 10**18);
        console2.log("amount requested %e", amount);    
        console2.log("Max borrow amount %e", _getUserLiquidityPriceUSD(user).sub((UD60x18.wrap(usersDebt.get(user))).div(UD60x18.wrap(10**ERC20(gho).decimals()))).mul(UD60x18.wrap(maxLTV)).div(UD60x18.wrap(100)).unwrap());
        //get user position price in USD, then check if borrow amount + debt already owed (adjusted to gho decimals) is inferior to maxLTV (80% = maxLTV/100)
        if(_getUserLiquidityPriceUSD(user).lte((UD60x18.wrap((amount+ usersDebt.get(user))).div(UD60x18.wrap(10**ERC20(gho).decimals()))).mul(UD60x18.wrap(maxLTV)).div(UD60x18.wrap(100)))){ 
            revert("user LTV is superior to maximum LTV"); //TODO add proper error message
        }
        usersDebt.set(user, usersDebt.get(user) + amount);
        IGhoToken(gho).mint(user, amount);
    
    }

    function viewGhoDebt(address user) public view returns (uint256){
        return usersDebt.get(user);
    }

    function repayGho(uint256 amount, address user) public returns (bool){
        //check if user has debt already
        if(usersDebt.get(user) < amount){
            revert("user debt is inferior to amount to repay");
        }
        //check if user has enough gho to repay, need to approve first then repay 
        bool isSuccess = ERC20(gho).transferFrom(user, address(this), amount); //send gho to this address then burning it
        if(!isSuccess){
            revert("transferFrom failed");
            return false;
        }else{
            IGhoToken(gho).burn(amount);
            usersDebt.set(user, usersDebt.get(user) - amount);
            return true;
        }
        
    }

    function _getUserLiquidityPriceUSD(address user) internal view returns (UD60x18){
        
        IPoolManager.PoolKey memory key = _getPoolKey();
        (uint160 sqrtPriceX96, int24 currentTick, , , , ) = poolManager.getSlot0(key.toId()); //curent price and tick of the pool
        UserLiquidity memory userCurrentPosition = userPosition[user];
        
        //Lower and Upper tick of the position
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
    
        //Use UD60x18 to convert token amount to decimal adjusted to avoid overflow errors
        UD60x18 token0amountUD60x18 = UD60x18.wrap(token0amount).div(UD60x18.wrap(10**ERC20(Currency.unwrap(key.currency0)).decimals()));
        UD60x18 token1amountUD60x18 = UD60x18.wrap(token1amount).div(UD60x18.wrap(10**ERC20(Currency.unwrap(key.currency1)).decimals()));

        //Price feed from Chainlink, convert to UD60x18 to avoid overflow errors
        UD60x18 ETHPrice = UD60x18.wrap(uint256(ETHPriceFeed.latestAnswer())).div(UD60x18.wrap(10**ETHPriceFeed.decimals()));
        UD60x18 USDCPrice = UD60x18.wrap(uint256(USDCPriceFeed.latestAnswer())).div(UD60x18.wrap(10**USDCPriceFeed.decimals()));

        //Price value of each token in the position
        UD60x18 token0Price = token0amountUD60x18.mul(ETHPrice);
        UD60x18 token1Price = token1amountUD60x18.mul(USDCPrice);
       
        //Price value of the position
        console2.log("position price not decimal adjusted %e", (token0Price.add(token1Price)).unwrap());

        //return price value of the position as UD60x18
        return token0Price.add(token1Price);
    }   


    function _getPositionUsdPrice(int24 tickLower, int24 tickUpper, uint128 liquidity) internal view returns (UD60x18){
        IPoolManager.PoolKey memory key = _getPoolKey();
        (uint160 sqrtPriceX96, int24 currentTick, , , , ) = poolManager.getSlot0(key.toId()); //curent price and tick of the pool
        
        //Lower and Upper tick of the position
        uint160 sqrtPriceLower = TickMath.getSqrtRatioAtTick(tickLower); //get price as decimal from Q64.96 format
        uint160 sqrtPriceUpper = TickMath.getSqrtRatioAtTick(tickUpper);
        uint256 token0amount;
        uint256 token1amount;

        //Price calculations on https://blog.uniswap.org/uniswap-v3-math-primer-2#how-to-calculate-current-holdings
        //Out of range, on the downside
        if(currentTick < tickLower){
            token0amount = SqrtPriceMath.getAmount0Delta(
                sqrtPriceLower,
                sqrtPriceUpper,
                liquidity,
                false
            );
            token1amount = 0;
        //Out of range, on the upside
        }else if(currentTick >= tickUpper){
            token0amount = 0;
            token1amount = SqrtPriceMath.getAmount1Delta(
                sqrtPriceLower,
                sqrtPriceUpper,
                liquidity,
                false
            );
        //in range position
        }else{
            token0amount = SqrtPriceMath.getAmount0Delta(
                sqrtPriceX96,
                sqrtPriceUpper,
                liquidity,
                false
            );
            token1amount = SqrtPriceMath.getAmount1Delta(
                sqrtPriceLower,
                sqrtPriceX96,
                liquidity,
                false
            );
        }
    
        //Use UD60x18 to convert token amount to decimal adjusted to avoid overflow errors
        UD60x18 token0amountUD60x18 = UD60x18.wrap(token0amount).div(UD60x18.wrap(10**ERC20(Currency.unwrap(key.currency0)).decimals()));
        UD60x18 token1amountUD60x18 = UD60x18.wrap(token1amount).div(UD60x18.wrap(10**ERC20(Currency.unwrap(key.currency1)).decimals()));

        //Price feed from Chainlink, convert to UD60x18 to avoid overflow errors
        UD60x18 ETHPrice = UD60x18.wrap(uint256(ETHPriceFeed.latestAnswer())).div(UD60x18.wrap(10**ETHPriceFeed.decimals()));
        UD60x18 USDCPrice = UD60x18.wrap(uint256(USDCPriceFeed.latestAnswer())).div(UD60x18.wrap(10**USDCPriceFeed.decimals()));

        //Price value of each token in the position
        UD60x18 token0Price = token0amountUD60x18.mul(ETHPrice);
        UD60x18 token1Price = token1amountUD60x18.mul(USDCPrice);
       
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

        console2.log("user liquidity %e", userLiquidity);
        console2.log("user tick lower", tickLower);
        console2.log("user tick upper", tickUpper);

    }

    function _checkLiquidationsAfterSwap() internal{
        for (uint i = 0; i < usersDebt.size(); i++) {
            address key = usersDebt.getKeyAtIndex(i);

            //check if user is liquidable
            if(_getUserLiquidityPriceUSD(key).lte((UD60x18.wrap(usersDebt.get(key))).div(UD60x18.wrap(10**ERC20(gho).decimals())).mul(UD60x18.wrap(maxLTV)).div(UD60x18.wrap(100)))){ 
                isUserLiquidable[key] = true;
                _liquidateUser(key);
        }
    }
    }

    function _liquidateUser(address user) internal{
        
    }

    function _canUserWithdraw(address user, int24 tickLower, int24 tickUpper, uint128 liquidity) internal view returns (bool){
        console2.log("user liquidity withdraw %e", liquidity);
        console2.log("user debt before withdraw %e", usersDebt.get(user) / 10**18);
        console2.log("user position price in USD before withdraw %e", _getUserLiquidityPriceUSD(user).unwrap() / 10**18);
        console2.log("UDx60 debt %e" , UD60x18.wrap(usersDebt.get(user)).div(UD60x18.wrap((10**ERC20(gho).decimals()))).unwrap());

        //check if debt / (position price - withdraw liquidity amount) is inferior to maxLTV (=77%)
        console2.log("position value user wants to withdraw %e", _getPositionUsdPrice(tickLower, tickUpper, liquidity).unwrap()/ 10**18);

        UD60x18 _positionValueAfterWithdraw = _getUserLiquidityPriceUSD(user).gte(_getPositionUsdPrice(tickLower, tickUpper, liquidity)) ? _getUserLiquidityPriceUSD(user).sub(_getPositionUsdPrice(tickLower, tickUpper, liquidity)) : UD60x18.wrap(0);
        console2.log("UDx60 position value after withdraw %e", _positionValueAfterWithdraw.unwrap());
        console2.log("ahahahah  ", _positionValueAfterWithdraw.isZero());
        if(_positionValueAfterWithdraw.isZero() && usersDebt.get(user) == 0){
            //If user has no debt and withdraw all his position, he can withdraw
            console2.log("case 1");
            return true;
        }else if(_positionValueAfterWithdraw.isZero() && usersDebt.get(user) > 0){
            //If user has debt and withdraw all his position, he cannot withdraw
            console2.log("case 2");
            return false;
        }
        if(!_positionValueAfterWithdraw.isZero() && (UD60x18.wrap(usersDebt.get(user)).div(UD60x18.wrap((10**ERC20(gho).decimals()))).div(_positionValueAfterWithdraw).lte(maxLTVUD60x18))){
            //If user has debt and withdraw part of his position, check if debt / (position price - withdraw liquidity amount) is inferior to maxLTV (=77%)
            return true;
        }else{
            //unhandled case, default to false to avoid user withdrawing more than he should
            return false;
        }
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
