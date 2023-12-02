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
import {BorrowHook} from "../src/BorrowHook.sol";



using CurrencyLibrary for Currency;

contract UniswapHooksTest is PRBTest, StdCheats {
    UniswapHooksFactory internal uniswapHooksFactory;
    MockERC20 internal token1;
    MockERC20 internal token2;
    BorrowHook internal deployedHooks;
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

                deployedHooks = BorrowHook(uniswapHooksFactory.deploy(owner, poolManager, salt));
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

        token1.approve(address(poolManager), type(uint256).max);
        token2.approve(address(poolManager), type(uint256).max);

        console2.log("Token1 balance before providing liquidity %e", token1.balanceOf(address(this)));
        console2.log("Token2 balance before providing liquidity %e", token2.balanceOf(address(this)));



        // lets execute all remaining hooks
        poolManager.modifyPosition(key, IPoolManager.ModifyPositionParams(-60*100, 60*6, 20e10)); //manage ranges with ticks

        _settleTokenBalance(Currency.wrap(address(WETH)));
        _settleTokenBalance(Currency.wrap(address(USDC)));

        poolManager.donate(key, 1e8, 1e8);

        console2.log("Token1 balance after providing liquidity %e", token1.balanceOf(address(this)));
        console2.log("Token2 balance after providing liquidity %e", token2.balanceOf(address(this)));



        //test borrow gho
        
        //address alice = makeAddr("alice");
        uint256 ghoBorrowAmount = 2000e18;
        deployedHooks.borrowGho(ghoBorrowAmount, address(this));
        console2.log("GHO balance of this test %e", IGhoToken(gho).balanceOf(address(this)));
        
        //test view gho debt
        uint256 debt = deployedHooks.viewGhoDebt(address(this));
        console2.log("GHO debt of this test %e", debt);

        
        

    
        //swap 1
        console2.log("Token1 balance before swap %e", token1.balanceOf(address(this)));
        console2.log("Token2 balance before swap %e", token2.balanceOf(address(this)));

        (uint160 sqrtPriceX96Current, int24 currentTick, , , , ) = poolManager.getSlot0(PoolIdLibrary.toId(key));
        uint160 maxSlippage = 2;




        // opposite action: poolManager.swap(key, IPoolManager.SwapParams(true, 100, TickMath.MIN_SQRT_RATIO * 1000));
        poolManager.swap(key, IPoolManager.SwapParams(false, 1e8, sqrtPriceX96Current + sqrtPriceX96Current*maxSlippage/100)); //false = buy eth with usdc


        _settleTokenBalance(Currency.wrap(address(WETH)));
        _settleTokenBalance(Currency.wrap(address(USDC)));


        console2.log("Token1 balance after swap 1 %e", token1.balanceOf(address(this)));
        console2.log("Token2 balance after swap  1 %e", token2.balanceOf(address(this)));

        //swap 2
        poolManager.swap(key, IPoolManager.SwapParams(true, 1e9, sqrtPriceX96Current - sqrtPriceX96Current*maxSlippage/100)); //true = sell eth for usdc

        _settleTokenBalance(Currency.wrap(address(WETH)));
        _settleTokenBalance(Currency.wrap(address(USDC)));


        console2.log("Token1 balance after swap %e", token1.balanceOf(address(this)));
        console2.log("Token2 balance after swap %e", token2.balanceOf(address(this)));

        //test repay gho
        ERC20(gho).approve(address(deployedHooks), type(uint256).max);
        deployedHooks.repayGho(debt, address(this));

        //test view gho debt after repaying
        debt = deployedHooks.viewGhoDebt(address(this));
        console2.log("GHO debt after repaying of this test %e", debt);



        return new bytes(0);
    }

    function _settleTokenBalance(Currency token) private {
        int256 unsettledTokenBalance = poolManager.getCurrencyDelta(0, token);

        if (unsettledTokenBalance == 0) {
            return;
        }

        if (unsettledTokenBalance < 0) {
            poolManager.take(token, msg.sender, uint256(-unsettledTokenBalance));
            return;
        }

        token.transfer(address(poolManager), uint256(unsettledTokenBalance));
        poolManager.settle(token);
    }

    function _getPoolKey() private view returns (IPoolManager.PoolKey memory) {
        return IPoolManager.PoolKey({
            currency0: Currency.wrap(address(WETH)),
            currency1: Currency.wrap(address(USDC)),
            fee: Fees.DYNAMIC_FEE_FLAG + Fees.HOOK_SWAP_FEE_FLAG + Fees.HOOK_WITHDRAW_FEE_FLAG, // 0xE00000 = 111
            tickSpacing: 60,
            hooks: BorrowHook(deployedHooks)
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
        deal(WETH, address(this), 10e18);
        deal(USDC, address(this), 100000e6);

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