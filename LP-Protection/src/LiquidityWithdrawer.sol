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

/**
 * @title Liquidity Withdrawer
 * @notice Emergency contract for removing liquidity when Drosera trap detects threats
 * @dev Called by Drosera response system with (address pair, uint256 amount) payload
 */
contract LiquidityWithdrawer {
    address public owner;
    address public droseraResponse;
    bool public paused;
    
    event EmergencyWithdrawal(address indexed pair, uint256 lpAmount, uint256 amount0, uint256 amount1);
    event PauseStateChanged(bool paused);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event DroseraResponseUpdated(address indexed newDroseraResponse);
    
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
        require(_droseraResponse != address(0), "Invalid Drosera response address");
        owner = msg.sender;
        droseraResponse = _droseraResponse;
        paused = false;
    }
    
    /**
     * @notice Emergency withdrawal function called by Drosera
     * @param pair The LP pair address to withdraw from
     * @param amount Amount of LP tokens to burn (0 = withdraw all available)
     * @dev This signature matches the TOML config: emergencyWithdraw(address,uint256)
     */
    function emergencyWithdraw(address pair, uint256 amount) external onlyDroseraOrOwner notPaused {
        IUniswapV2Pair lpPair = IUniswapV2Pair(pair);
        uint256 balance = lpPair.balanceOf(address(this));
        require(balance > 0, "No LP tokens to withdraw");
        
        uint256 withdrawAmount = amount == 0 ? balance : amount;
        require(withdrawAmount <= balance, "Insufficient LP balance");
        
        // Transfer LP tokens to pair for burning
        require(lpPair.transfer(pair, withdrawAmount), "LP transfer failed");
        
        // Burn LP tokens and receive underlying tokens
        (uint256 amount0, uint256 amount1) = lpPair.burn(address(this));
        
        emit EmergencyWithdrawal(pair, withdrawAmount, amount0, amount1);
    }
    
    /**
     * @notice Alternative handler for flexible payload decoding
     * @param payload Encoded (address pair, uint256 amount) data
     * @dev Can be used with TOML: response_function = "handle(bytes)"
     */
    function handle(bytes calldata payload) external onlyDroseraOrOwner notPaused {
        (address pair, uint256 amount) = abi.decode(payload, (address, uint256));
        emergencyWithdraw(pair, amount);
    }
    
    /**
     * @notice Withdraw any ERC20 tokens held by this contract
     * @param token Token address
     * @param to Recipient address
     * @param amount Amount to withdraw (0 = all)
     */
    function withdrawToken(address token, address to, uint256 amount) external onlyOwner {
        IERC20 erc20 = IERC20(token);
        uint256 balance = erc20.balanceOf(address(this));
        uint256 withdrawAmount = amount == 0 ? balance : amount;
        
        require(withdrawAmount > 0 && withdrawAmount <= balance, "Invalid amount");
        require(erc20.transfer(to, withdrawAmount), "Transfer failed");
    }
    
    /**
     * @notice Withdraw ETH held by this contract
     * @param to Recipient address
     */
    function withdrawETH(address payable to) external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");
        (bool success, ) = to.call{value: balance}("");
        require(success, "ETH transfer failed");
    }
    
    /**
     * @notice Pause or unpause emergency withdrawals
     * @param _paused New pause state
     */
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit PauseStateChanged(_paused);
    }
    
    /**
     * @notice Update the Drosera response contract address
     * @param _droseraResponse New Drosera response address
     * @dev Critical: This must be the Drosera executor address, not the trap
     */
    function setDroseraResponse(address _droseraResponse) external onlyOwner {
        require(_droseraResponse != address(0), "Invalid address");
        droseraResponse = _droseraResponse;
        emit DroseraResponseUpdated(_droseraResponse);
    }
    
    /**
     * @notice Transfer ownership to a new address
     * @param newOwner New owner address
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid new owner");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
    
    /**
     * @notice Get LP token balance for a specific pair
     * @param pair LP pair address
     * @return LP token balance held by this contract
     */
    function lpBalance(address pair) external view returns (uint256) {
        return IUniswapV2Pair(pair).balanceOf(address(this));
    }
    
    /**
     * @notice Allow contract to receive ETH
     */
    receive() external payable {}
}
