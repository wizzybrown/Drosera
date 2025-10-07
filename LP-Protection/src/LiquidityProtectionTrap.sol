// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {EventLog, EventFilter} from "drosera-network-contracts/src/libraries/Events.sol";
import {Trap} from "drosera-network-contracts/src/Trap.sol";

/**
 * @title LiquidityProtectionTrap
 * @dev Monitors user's LP token balance and triggers withdrawal when position drops by 50%+
 * @notice Stateless design - config embedded in collect payload for Drosera compatibility
 */
contract LiquidityProtectionTrap is Trap {
    
    // Hardcoded configuration (replace with your actual addresses)
    address constant MONITORED_USER = 0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb; // Replace with actual user
    address constant LIQUIDITY_POOL = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc; // Replace with actual pool
    
    // Events to monitor
    string constant TRANSFER_SIGNATURE = "Transfer(address,address,uint256)";
    string constant SYNC_SIGNATURE = "Sync(uint112,uint112)";
    
    // Threshold: 50% drop = 5000 basis points
    uint256 constant DROP_THRESHOLD = 5000;
    uint256 constant BASIS_POINTS = 10000;
    
    function eventLogFilters() public pure override returns (EventFilter[] memory) {
        EventFilter[] memory filters = new EventFilter[](2);
        
        // Monitor LP token transfers
        filters[0] = EventFilter({
            contractAddress: LIQUIDITY_POOL,
            signature: TRANSFER_SIGNATURE
        });
        
        // Monitor reserve updates
        filters[1] = EventFilter({
            contractAddress: LIQUIDITY_POOL,
            signature: SYNC_SIGNATURE
        });
        
        return filters;
    }
    
    function collect() external view override returns (bytes memory) {
        EventLog[] memory logs = getEventLogs();
        
        uint256 userLPBalance = 0;
        uint256 totalSupply = 0;
        uint112 reserve0 = 0;
        uint112 reserve1 = 0;
        
        // Process Transfer events to calculate user's LP balance
        for (uint256 i = 0; i < logs.length; i++) {
            EventLog memory log = logs[i];
            
            if (log.emitter != LIQUIDITY_POOL) continue;
            
            // Handle Transfer events for LP token
            if (log.topics.length >= 3 && log.topics[0] == keccak256(bytes(TRANSFER_SIGNATURE))) {
                address from = address(uint160(uint256(log.topics[1])));
                address to = address(uint160(uint256(log.topics[2])));
                uint256 amount = abi.decode(log.data, (uint256));
                
                // Update user balance based on transfers
                if (to == MONITORED_USER) {
                    userLPBalance += amount;
                }
                if (from == MONITORED_USER) {
                    userLPBalance = userLPBalance > amount ? userLPBalance - amount : 0;
                }
                
                // Track total supply changes (mints from 0x0, burns to 0x0)
                if (from == address(0)) {
                    totalSupply += amount;
                }
                if (to == address(0)) {
                    totalSupply = totalSupply > amount ? totalSupply - amount : 0;
                }
            }
            
            // Handle Sync events for reserve tracking
            else if (log.topics.length > 0 && log.topics[0] == keccak256(bytes(SYNC_SIGNATURE))) {
                (reserve0, reserve1) = abi.decode(log.data, (uint112, uint112));
            }
        }
        
        // Return: userLPBalance, totalSupply, reserve0, reserve1, timestamp, user, pool
        return abi.encode(
            userLPBalance,
            totalSupply,
            reserve0,
            reserve1,
            block.timestamp,
            MONITORED_USER,
            LIQUIDITY_POOL
        );
    }
    
    function shouldRespond(bytes[] calldata data) external pure override returns (bool, bytes memory) {
        if (data.length < 2) {
            return (false, "");
        }
        
        // Decode current state
        (
            uint256 currentLPBalance,
            uint256 currentTotalSupply,
            uint112 currentReserve0,
            uint112 currentReserve1,
            ,
            address monitoredUser,
            address liquidityPool
        ) = abi.decode(data[0], (uint256, uint256, uint112, uint112, uint256, address, address));
        
        // Decode previous state
        (
            uint256 prevLPBalance,
            uint256 prevTotalSupply,
            uint112 prevReserve0,
            uint112 prevReserve1,
            ,,
        ) = abi.decode(data[1], (uint256, uint256, uint112, uint112, uint256, address, address));
        
        // Check for significant LP balance drop
        if (prevLPBalance > 0 && currentLPBalance < prevLPBalance) {
            uint256 balanceDrop = prevLPBalance - currentLPBalance;
            uint256 dropPercentage = (balanceDrop * BASIS_POINTS) / prevLPBalance;
            
            if (dropPercentage >= DROP_THRESHOLD) {
                // Return payload matching responder: (pair, amount)
                // amount=0 means withdraw all LP tokens held by responder
                return (
                    true,
                    abi.encode(liquidityPool, uint256(0))
                );
            }
        }
        
        // Check for significant reserve drops (rug pull indicator)
        if (prevReserve0 > 0 && prevReserve1 > 0) {
            uint256 reserve0Drop = prevReserve0 > currentReserve0 ? 
                ((uint256(prevReserve0) - uint256(currentReserve0)) * BASIS_POINTS) / uint256(prevReserve0) : 0;
            uint256 reserve1Drop = prevReserve1 > currentReserve1 ? 
                ((uint256(prevReserve1) - uint256(currentReserve1)) * BASIS_POINTS) / uint256(prevReserve1) : 0;
            
            if (reserve0Drop >= DROP_THRESHOLD || reserve1Drop >= DROP_THRESHOLD) {
                // Trigger emergency withdrawal on significant reserve drop
                return (
                    true,
                    abi.encode(liquidityPool, uint256(0))
                );
            }
        }
        
        return (false, "");
    }
}
