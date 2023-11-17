// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { console2 } from "forge-std/console2.sol";
import {ICreditDelegationToken} from "@aave/core-v3/contracts/interfaces/ICreditDelegationToken.sol";



contract MultiDelegateCall {
    error DelegatecallFailed();

    function multiDelegatecall(
        bytes[] memory data
    ) external payable returns (bytes[] memory results) {
        results = new bytes[](data.length);

        for (uint i; i < data.length; i++) {
            (bool ok, bytes memory res) = address(this).delegatecall(data[i]);
            if (!ok) {
                revert DelegatecallFailed();
            }
            results[i] = res;
        }
    }
}


contract Helper {
    function getApproveDelegateData(address delegatee, address debtToken, uint256 amount) external pure returns (bytes memory) {
        return abi.encodeWithSelector(ICreditDelegationToken(debtToken).approveDelegation.selector, delegatee, amount);
    }

    
}