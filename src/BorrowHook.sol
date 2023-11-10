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


contract BorrowHook is BaseHook, IHookFeeManager, IDynamicFeeManager {
    address public owner;
    address public ghoVariableDebtToken = 0x3FEaB6F8510C73E05b8C0Fdf96Df012E3A144319;

    address public gho = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f;
    address public debtHandler;

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
        pure
        override
        returns (bytes4)
    {
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
}
