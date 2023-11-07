// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import { IPoolManager, UniswapHooks } from "./UniswapHooks.sol";

contract UniswapHooksFactory {
    address public debtHandler;
    function deploy(address owner, IPoolManager poolManager, bytes32 salt) external returns (address) {
        return address(new UniswapHooks{salt: salt}(owner, poolManager, debtHandler));
    }

    function getPrecomputedHookAddress(
        address owner,
        IPoolManager poolManager,
        bytes32 salt
    )
        external
        view
        returns (address)
    {
        bytes32 bytecodeHash =
            keccak256(abi.encodePacked(type(UniswapHooks).creationCode, abi.encode(owner, poolManager)));
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, bytecodeHash));
        return address(uint160(uint256(hash)));
    }
}
