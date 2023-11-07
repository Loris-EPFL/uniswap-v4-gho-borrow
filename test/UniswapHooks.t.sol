// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import { PRBTest } from "@prb/test/PRBTest.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";

import { PoolManager, Currency } from "@uniswap/v4-core/contracts/PoolManager.sol";
import { TickMath } from "@uniswap/v4-core/contracts/libraries/TickMath.sol";
import { Fees } from "@uniswap/core-v4/contracts/Fees.sol";
import { CurrencyLibrary } from "@uniswap/core-v4/contracts/types/Currency.sol";
import { TestERC20 } from "@uniswap/v4-core/contracts/test/TestERC20.sol";
import {
    IPoolManager, Hooks, IHooks, BaseHook, BalanceDelta
} from "@uniswap-periphery/v4-periphery/contracts/BaseHook.sol";

import { UniswapHooksFactory } from "../src/UniswapHooksFactory.sol";

using CurrencyLibrary for Currency;

contract UniswapHooksTest is PRBTest, StdCheats {
    UniswapHooksFactory internal uniswapHooksFactory;
    TestERC20 internal token1;
    TestERC20 internal token2;
    IHooks internal deployedHooks;
    IPoolManager internal poolManager;

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

                // First we need two tokens
                token1 = new TestERC20(3000);
                token2 = new TestERC20(3000);
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

        // lets execute all remaining hooks
        poolManager.modifyPosition(key, IPoolManager.ModifyPositionParams(TickMath.MIN_TICK, TickMath.MAX_TICK, 1000));
        poolManager.donate(key, 100, 100);

        // opposite action: poolManager.swap(key, IPoolManager.SwapParams(true, 100, TickMath.MIN_SQRT_RATIO * 1000));
        poolManager.swap(key, IPoolManager.SwapParams(false, 100, TickMath.MAX_SQRT_RATIO / 1000));

        _settleTokenBalance(Currency.wrap(address(token1)));
        _settleTokenBalance(Currency.wrap(address(token2)));

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

        //token.transfer(address(poolManager), uint256(unsettledTokenBalance));
        poolManager.settle(token);
    }

    function _getPoolKey() private view returns (IPoolManager.PoolKey memory) {
        /*
        return IPoolManager.PoolKey({
            currency0: Currency.wrap(address(token1)),
            currency1: Currency.wrap(address(token2)),
            fee: Fees.DYNAMIC_FEE_FLAG + Fees.HOOK_SWAP_FEE_FLAG + Fees.HOOK_WITHDRAW_FEE_FLAG, // 0xE00000 = 111
            tickSpacing: 1,
            hooks: IHooks(deployedHooks)
        });
        */
    }

    function _doesAddressStartWith(address _address, uint160 _prefix) private pure returns (bool) {
        return uint160(_address) / (2 ** (8 * (19))) == _prefix;
    }
}
