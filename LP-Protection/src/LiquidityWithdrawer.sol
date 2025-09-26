// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IUniswapV2Pair {
    function burn(address to) external returns (uint256 amount0, uint256 amount1);
    function transfer(address to, uint256 value) external returns (bool);
    function balanceOf(address owner) external view returns (uint256);
}

/// @title Liquidity Withdrawer
/// @notice Emergency contract for removing liquidity when suspicious activity is detected
contract LiquidityWithdrawer {
    address public owner;
    address public droseraResponse;
    bool public paused;
    
    event EmergencyWithdrawal(address indexed pair, uint256 amount0, uint256 amount1);
    event PauseStateChanged(bool paused);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    
    modifier onlyDroseraOrOwner() {
        require(msg.sender == droseraResponse || msg.sender == owner, "Not authorized");
        _;
    }
    
    modifier notPaused() {
        require(!paused, "Contract paused");
        _;
    }
    
    constructor(address _droseraResponse) {
        owner = msg.sender;
        droseraResponse = _droseraResponse;
        paused = false;
    }
    
    function emergencyWithdraw(address pair, uint256 amount) external onlyDroseraOrOwner notPaused {
        IUniswapV2Pair lpPair = IUniswapV2Pair(pair);
        uint256 balance = lpPair.balanceOf(address(this));
        require(balance > 0, "No LP tokens to withdraw");
        
        uint256 withdrawAmount = amount == 0 ? balance : amount;
        require(withdrawAmount <= balance, "Insufficient LP balance");
        
        lpPair.transfer(pair, withdrawAmount);
        (uint256 amount0, uint256 amount1) = lpPair.burn(address(this));
        
        emit EmergencyWithdrawal(pair, amount0, amount1);
    }
    
    function withdrawToken(address token, address to, uint256 amount) external onlyOwner {
        IERC20 erc20 = IERC20(token);
        uint256 balance = erc20.balanceOf(address(this));
        uint256 withdrawAmount = amount == 0 ? balance : amount;
        
        require(withdrawAmount <= balance, "Insufficient balance");
        require(erc20.transfer(to, withdrawAmount), "Transfer failed");
    }
    
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit PauseStateChanged(_paused);
    }
    
    function setDroseraResponse(address _droseraResponse) external onlyOwner {
        droseraResponse = _droseraResponse;
    }
    
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid new owner");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
    
    function getLPBalance(address pair) external view returns (uint256) {
        return IUniswapV2Pair(pair).balanceOf(address(this));
    }
}
