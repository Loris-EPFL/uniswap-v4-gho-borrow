// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";


contract debtHandler {

    // Token addresses
    address public tokenA;
    address public tokenB;

    // AToken addresses
    address public AtokenA;
    address public AtokenB;

    mapping(address => uint256) public userDebt;
    mapping(address => uint256) public userCollateral;

    IPoolManager public poolManager;

    constructor(IPoolManager _poolManager, address tokenA_, address tokenB_) {
    poolManager = _poolManager;
    
        
    tokenA = tokenA_;
    tokenB = tokenB_;
}


    function depositCollateral(uint256 amount) public {
        userCollateral[msg.sender] += amount;
    }

    function withdrawCollateral(uint256 amount) public {
        require(userCollateral[msg.sender] >= amount, "not enough collateral");
        userCollateral[msg.sender] -= amount;
    }

    function repayDebt(uint256 amount) public {
        require(userDebt[msg.sender] >= amount, "not enough debt");
        userDebt[msg.sender] -= amount;
    }

    function borrow(uint256 amount) public {
        require(userCollateral[msg.sender] >= amount, "not enough collateral");
        userDebt[msg.sender] += amount;
    }
}
