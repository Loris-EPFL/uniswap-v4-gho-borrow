// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import { PRBTest } from "@prb/test/PRBTest.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";


import { PoolManager, Currency } from "@uniswap/v4-core/contracts/PoolManager.sol";
import { TickMath } from "@uniswap/v4-core/contracts/libraries/TickMath.sol";
import { Fees } from "@uniswap/core-v4/contracts/Fees.sol";
import { CurrencyLibrary } from "@uniswap/core-v4/contracts/types/Currency.sol";
import { TestERC20 } from "@uniswap/v4-core/contracts/test/TestERC20.sol";
import {
    IPoolManager, Hooks, IHooks, BaseHook, BalanceDelta
} from "@uniswap-periphery/v4-periphery/contracts/BaseHook.sol";

import { UniswapHooksFactory } from "../src/UniswapHooksFactory.sol";

import {IAToken} from "@aave/core-v3/contracts/interfaces/IAToken.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";

//import {PoolKey, PoolId} from "@uniswap/v3-core/contracts/libraries/PoolVariables.sol";
import {IGhoToken} from '@aave/gho/gho/interfaces/IGhoToken.sol';
import {AccessControl} from '@openzeppelin/contracts/access/AccessControl.sol';


using CurrencyLibrary for Currency;

contract InitPoolTest is PRBTest, StdCheats, AccessControl{

    function setUp() public virtual {
        //uniswapHooksFactory = new UniswapHooksFactory();
    }
    
    address public Aeth = 0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8;
    IAToken public aeth = IAToken(Aeth);
    address public Ausdc = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;
    IAToken public ausdc = IAToken(Ausdc);

    address public gho = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f;


    //Uniswap v4 pool logic
    //PoolKey poolKey;
    //PoolId poolId;
    

    function testInit() external{
        address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        IPool AavePool = IPool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2); //Aave Mainnet pool address
        address owner = 0x388C818CA8B9251b393131C08a736A67ccB19297;
        address alice = makeAddr("alice");
        console2.log("alice's Address", alice);

        //poolManager = IPoolManager(address(new PoolManager(type(uint256).max)));

        //mint Aeth by depositing into pool
        deal(WETH, alice, 100e18);
        deal(USDC, alice, 10000e6);

        //prank as alice adress
        vm.startPrank(alice);
        console2.log("alice's WETH balance", ERC20(WETH).balanceOf(alice));
        ERC20(WETH).approve(address(AavePool), type(uint256).max);
        ERC20(USDC).approve(address(AavePool), type(uint256).max);

        AavePool.supply(WETH, 1e18, alice,0);
        AavePool.supply(USDC, 1000e6, alice,0);
        console2.log(aeth.balanceOf(alice));
        console2.log(ausdc.balanceOf(alice));
        vm.stopPrank();
    }

    function testAddFacilitator() external{
        //need FACILITATOR_MANAGER_ROLE to address to add hook as faciliator
        address whitelistedManager = 0x5300A1a15135EA4dc7aD5a167152C01EFc9b192A; //whitelisted address of aave dao

        bytes32 FacilitatorRole = (IGhoToken(gho).FACILITATOR_MANAGER_ROLE());

        
        address hookAddress = address(this);
        uint128 bucketCapacity = 100000e18;
        vm.startPrank(whitelistedManager);
        IGhoToken(gho).addFacilitator(hookAddress, "BorrowHook", bucketCapacity);
       
        vm.stopPrank();

        IGhoToken(gho).mint(hookAddress, 100e18);
        console2.log("GHO balance", IGhoToken(gho).balanceOf(hookAddress));

    }
    /*
    function setUp() public{
        poolKey = PoolKey(Currency.wrap(address(aeth)), Currency.wrap(address(ausdc)), 3000, 60, twamm);
        poolId = poolKey.toId();
    }

    function _getPoolKey() private view returns (IPoolManager.PoolKey memory) {
        
        return IPoolManager.PoolKey({
            currency0: Currency.wrap(address(aeth)),
            currency1: Currency.wrap(address(ausdc)),
            fee: 0xE00000, // 0xE00000 = 111
            tickSpacing: 1,
            hooks: IHooks(deployedHooks)
        });
        
    }
    */
   
    
}