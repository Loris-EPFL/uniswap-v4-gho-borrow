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
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { StdCheats } from "forge-std/StdCheats.sol";




contract BorrowHook is BaseHook, IHookFeeManager, IDynamicFeeManager, StdCheats {
    address public owner;
    address public ghoVariableDebtToken = 0x3FEaB6F8510C73E05b8C0Fdf96Df012E3A144319;

    address public GhoStableDebtToken = 0x05b435C741F5ab03C2E6735e23f1b7Fe01Cc6b22;

    address public gho = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f;

    address  Aeth = 0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8;
    address  Ausdc = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;

    address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address usdcVariableDebt = 0x72E95b8931767C79bA4EeE721354d6E99a61D004;
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    //Aave Mainnet pool address
    IPool AavePool = IPool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2); 


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
        address hookAdress = address(this);
        (bool success, bytes memory returndata) = address(poolManager).call{value: msg.value, gas: 500000}
        (abi.encodeWithSignature("ICreditDelegationToken(ghoVariableDebtToken).approveDelegation", hookAdress, type(uint256).max)
        );
        /*
        ICreditDelegationToken(ghoVariableDebtToken).approveDelegation(
            address(this), 
            type(uint256).max
            );
        */
        console2.log("approved delegation ?", success);
        //console2.log("approved delegation ?", returndata);
        
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
        override
        returns (bytes4)
    {
        
        //replace with gho's variable debt token interface or stable debt ???
        ICreditDelegationToken(ghoVariableDebtToken).approveDelegation(
            address(this), 
            type(uint256).max
            ); //approve max gho debt to debtHandler contract
        
        //IPoolManager(poolManager).getLiquidity(poolManager.); //set fee manager to this contract
        console2.log("address of poolManager", address(poolManager));   
        console2.log("Approved max credit delegeation for ", address(this));

        _mintTokens(); //mint Aave Aeth and Ausdc tokens from Aave lendingPool

        console2.log("balance of AETH", ERC20(Aeth).balanceOf(address(poolManager)));
        console2.log("balance of AUSDC", ERC20(Ausdc).balanceOf(address(poolManager)));

        console2.log("balance of AETH", ERC20(Aeth).balanceOf(address(this)));
        console2.log("balance of AUSDC", ERC20(Ausdc).balanceOf(address(this)));

        (uint totalCollateralETH, uint totalDebtETH, uint availableBorrowsETH, uint currentLiquidationThreshold, uint ltv, uint healthFactor) = AavePool.getUserAccountData(address(this));
        (uint totalCollateralPool, uint totalDebtPool, uint availableBorrowsPOOl, uint currentLiquidationThresholdPOOL, uint ltvPool, uint healthFactorPool) = AavePool.getUserAccountData(address(poolManager));

        console2.log("totalCollateralETH", totalCollateralETH);
        console2.log("totalCollateralPool", totalCollateralPool);

        /*
        AavePool.borrow(gho, 10e6, 2, 0, address(this));
        console2.log("Borrowed %e gho", ERC20(gho).balanceOf(address(this)));
        */
        
        console2.log("afterInitialize");
        return IHooks.afterInitialize.selector;
    }

    /// @inheritdoc IHooks
    function beforeModifyPosition(
        address, // sender
        IPoolManager.PoolKey calldata, // key
        IPoolManager.ModifyPositionParams calldata // params
    )
        external
        pure
        override
        returns (bytes4)
    {
        console2.log("beforeModifyPosition");
        return IHooks.beforeModifyPosition.selector;
    }

    /// @inheritdoc IHooks
    function afterModifyPosition(
        address, // sender
        IPoolManager.PoolKey calldata, // key
        IPoolManager.ModifyPositionParams calldata, // params
        BalanceDelta // delta
    )
        external
        override
        returns (bytes4)
    {
        //Borrow in name of PoolManager
        AavePool.borrow(gho, 10e6, 2, 0, address(poolManager));
        console2.log("Borrowed %e gho", ERC20(gho).balanceOf(address(this)));

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

    //helper function to mint Aave Aeth and Ausdc tokens from Aave lendingPool
    function _mintTokens() internal{
        address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        IPool AavePool = IPool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2); //Aave Mainnet pool address
        address owner = 0x388C818CA8B9251b393131C08a736A67ccB19297;
 
        //mint Aeth and Ausdc by depositing into pool
        deal(WETH, address(this), 100e18);
        deal(usdc, address(this), 10000e6);

        console2.log("hook's WETH balance", ERC20(WETH).balanceOf(address(this)));
        ERC20(WETH).approve(address(AavePool), type(uint256).max);
        ERC20(USDC).approve(address(AavePool), type(uint256).max);

        AavePool.supply(WETH, 1e18, address(this),0);
        AavePool.supply(USDC, 1000e6, address(this),0);
        console2.log(ERC20(Aeth).balanceOf(address(this)));
        console2.log(ERC20(Ausdc).balanceOf(address(this)));
        ERC20(Aeth).transfer(address(poolManager), ERC20(Aeth).balanceOf(address(this))/2);
        ERC20(Ausdc).transfer(address(poolManager), ERC20(Ausdc).balanceOf(address(this))/2);
    
    }

    function lockAcquired(uint256, /* id */ bytes calldata data)
        external
        virtual
        override
        poolManagerOnly
        returns (bytes memory)
    {
        (bool success, bytes memory returnData) = address(this).call(data);
        address DaiVariableDebt = 0xcF8d0c70c850859266f5C338b38F9D663181C314;
        ICreditDelegationToken(DaiVariableDebt).approveDelegation(
            address(this), 
            type(uint256).max
            );
        console2.log("call address vs poolManager address", address(this), address(poolManager));
        if (success) return returnData;
        if (returnData.length == 0) revert LockFailure();
        // if the call failed, bubble up the reason
        /// @solidity memory-safe-assembly
        assembly {
            revert(add(returnData, 32), mload(returnData))
        }
    }
}
