// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import { PRBTest } from "@prb/test/PRBTest.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";

import { PoolManager, Currency } from "@uniswap/v4-core/contracts/PoolManager.sol";
import { TickMath } from "@uniswap/v4-core/contracts/libraries/TickMath.sol";
import { Fees } from "@uniswap/v4-core/contracts/libraries/Fees.sol";
import { CurrencyLibrary } from "@uniswap/v4-core/contracts/libraries/CurrencyLibrary.sol";
import { TestERC20 } from "@uniswap/v4-core/contracts/test/TestERC20.sol";
import {MockERC20} from "@uniswap/v4-core/test/foundry-tests/utils/MockERC20.sol";
import {
    IPoolManager, Hooks, IHooks, BaseHook, BalanceDelta
} from "@uniswap-periphery/v4-periphery/contracts/BaseHook.sol";

import { UniswapHooksFactory } from "../src/UniswapHooksFactory.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IAToken} from "@aave/core-v3/contracts/interfaces/IAToken.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {InitPoolTest} from "./InitPool.t.sol";
import {IGhoToken} from '@aave/gho/gho/interfaces/IGhoToken.sol';
import {PoolIdLibrary} from "@uniswap/v4-core/contracts/libraries/PoolId.sol";



using CurrencyLibrary for Currency;

contract UniswapHooksTest is PRBTest, StdCheats {
    UniswapHooksFactory internal uniswapHooksFactory;
    MockERC20 internal token1;
    MockERC20 internal token2;
    IHooks internal deployedHooks;
    IPoolManager internal poolManager;

    
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address gho = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f;

   


    function setUp() public virtual {
        uniswapHooksFactory = new UniswapHooksFactory();
    }

    function test_Example() external {
        address owner = 0x388C818CA8B9251b393131C08a736A67ccB19297;
        poolManager = IPoolManager(address(new PoolManager(type(uint256).max)));

        for (uint256 i = 0; i < 1500; i++) {
            bytes32 salt = bytes32(i);
            address expectedAddress = uniswapHooksFactory.getPrecomputedHookAddress(owner, poolManager, salt);

            // 0xff = 11111111 = all hooks enabled
            if (_doesAddressStartWith(expectedAddress, 0xff)) {
                console2.log("Found hook address", expectedAddress, "with salt of", i);

                deployedHooks = IHooks(uniswapHooksFactory.deploy(owner, poolManager, salt));
                assertEq(address(deployedHooks), expectedAddress, "address is not as expected");

                // Let's test all the hooks

                IPoolManager.PoolKey memory key = _getPoolKey();



                // First we need two tokens
                token1 = MockERC20(Currency.unwrap(key.currency0));
                token2 = MockERC20(Currency.unwrap(key.currency1));
                
                //call the mint token helper function to freemint tokens
                _mintTokens();

                //add hook as faciliator
               AddFacilitator(address(deployedHooks));

               (uint256 bukcet, ) = IGhoToken(gho).getFacilitatorBucket(address(deployedHooks));

                console2.log("bucket capacity", bukcet);

                console2.log("Token1 address", address(token1));
                console2.log("Token1 balance", token1.balanceOf(address(this)));
                console2.log("Token2 address", address(token2));
                console2.log("Token2 balance", token2.balanceOf(address(this)));
                token1.approve(address(poolManager), type(uint256).max);
                token2.approve(address(poolManager), type(uint256).max);

                // sqrt(2) = 79_228_162_514_264_337_593_543_950_336 as Q64.96
                poolManager.initialize(_getPoolKey(), 79_228_162_514_264_337_593_543_950_336);
                poolManager.lock(new bytes(0));

                return;
            }
        }

        revert("No salt found");
    }

    function lockAcquired(uint256, bytes calldata) external returns (bytes memory) {
        IPoolManager.PoolKey memory key = _getPoolKey();

        // First we need two tokens
        token1 = MockERC20(Currency.unwrap(key.currency0));
        token2 = MockERC20(Currency.unwrap(key.currency1));

        console2.log("Token1 balance before providing liquidity %e", token1.balanceOf(address(this)));
        console2.log("Token2 balance before providing liquidity %e", token2.balanceOf(address(this)));


        // lets execute all remaining hooks
        poolManager.modifyPosition(key, IPoolManager.ModifyPositionParams(-60*6, 60*6, 10e10)); //manage ranges with ticks
        poolManager.donate(key, 10e6, 1000e6);
    
        //swap 1
        console2.log("Token1 balance before swap %e", token1.balanceOf(address(this)));
        console2.log("Token2 balance before swap %e", token2.balanceOf(address(this)));

        (uint160 sqrtPriceX96Current, int24 currentTick, , , , ) = poolManager.getSlot0(PoolIdLibrary.toId(key));
        uint160 maxSlippage = 2;


        // opposite action: poolManager.swap(key, IPoolManager.SwapParams(true, 100, TickMath.MIN_SQRT_RATIO * 1000));
        poolManager.swap(key, IPoolManager.SwapParams(false, 2e8, sqrtPriceX96Current + sqrtPriceX96Current*maxSlippage/100)); //false = buy eth with usdc


        _settleTokenBalance(Currency.wrap(address(WETH)));
        _settleTokenBalance(Currency.wrap(address(USDC)));


        console2.log("Token1 balance after swap %e", token1.balanceOf(address(this)));
        console2.log("Token2 balance after swap %e", token2.balanceOf(address(this)));

        //swap 2
        console2.log("Token1 balance before swap %e", token1.balanceOf(address(this)));
        console2.log("Token2 balance before swap %e", token2.balanceOf(address(this)));

        poolManager.swap(key, IPoolManager.SwapParams(true, 2e9, sqrtPriceX96Current - sqrtPriceX96Current*maxSlippage/100)); //true = sell eth for usdc

        _settleTokenBalance(Currency.wrap(address(WETH)));
        _settleTokenBalance(Currency.wrap(address(USDC)));


        console2.log("Token1 balance after swap %e", token1.balanceOf(address(this)));
        console2.log("Token2 balance after swap %e", token2.balanceOf(address(this)));


        return new bytes(0);
    }

    function _settleTokenBalance(Currency token) private {
        int256 unsettledTokenBalance = poolManager.getCurrencyDelta(0, token);

        console2.log("unsettledTokenBalance", unsettledTokenBalance);

        if (unsettledTokenBalance == 0) {
            return;
        }

        if (unsettledTokenBalance < 0) {
            console2.log("msg sender is ", msg.sender);
            //poolManager.take(token, msg.sender, uint256(-unsettledTokenBalance));
            poolManager.take(token, address(this), uint256(-unsettledTokenBalance)); //take from pool manager to test address because otherwise it sends from poolManager to itslef

            return;
        }

        
        if(unsettledTokenBalance > 0){
            console2.log("msg sender is ", msg.sender);
            poolManager.mint(token, (msg.sender), uint256(unsettledTokenBalance));

        }
        

        //token.transfer(address(poolManager), uint256(unsettledTokenBalance));
        token.transfer(address(msg.sender), uint256(unsettledTokenBalance));

        poolManager.settle(token);
    }

    function _getPoolKey() private view returns (IPoolManager.PoolKey memory) {
        return IPoolManager.PoolKey({
            currency0: Currency.wrap(address(WETH)),
            currency1: Currency.wrap(address(USDC)),
            fee: Fees.DYNAMIC_FEE_FLAG + Fees.HOOK_SWAP_FEE_FLAG + Fees.HOOK_WITHDRAW_FEE_FLAG, // 0xE00000 = 111
            tickSpacing: 60,
            hooks: IHooks(deployedHooks)
        });
    }

    function _doesAddressStartWith(address _address, uint160 _prefix) private pure returns (bool) {
        return uint160(_address) / (2 ** (8 * (19))) == _prefix;
    }

    //helper function to mint Aave Aeth and Ausdc tokens from Aave lendingPool
    function _mintTokens() internal{
        address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address owner = 0x388C818CA8B9251b393131C08a736A67ccB19297;
 
        //mint Aeth and Ausdc by depositing into pool
        deal(WETH, address(this), 1e18);
        deal(USDC, address(this), 10000e6);

        console2.log("hook's WETH balance", ERC20(WETH).balanceOf(address(this)));
        console2.log("hook's USDC balance", ERC20(USDC).balanceOf(address(this)));
    
    }

    //Helper function to add hook as faciliator
    function AddFacilitator(address faciliator) public{
        //need FACILITATOR_MANAGER_ROLE to address to add hook as faciliator
        address whitelistedManager = 0x5300A1a15135EA4dc7aD5a167152C01EFc9b192A; //whitelisted address of aave dao

        bytes32 FacilitatorRole = (IGhoToken(gho).FACILITATOR_MANAGER_ROLE());

        
        address hookAddress = address(this);
        uint128 bucketCapacity = 100000e18;
        vm.startPrank(whitelistedManager);
        IGhoToken(gho).addFacilitator(faciliator, "BorrowHook", bucketCapacity);
       
        vm.stopPrank();

        console2.log("GHO balance", IGhoToken(gho).balanceOf(hookAddress));

    }
}