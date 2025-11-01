// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {EventLog, EventFilter} from "drosera-network-contracts/src/libraries/Events.sol";
import {Trap} from "drosera-network-contracts/src/Trap.sol";

/**
 * @title LiquidityProtectionTrap
 * @dev Monitors user's LP token balance and triggers withdrawal when position drops by 50%+
 * @notice Uses on-chain balance reads for accuracy - event logs optional for reserve monitoring
 */

/// @notice Minimal interface for Uniswap V2 Pair
interface IUniswapV2Pair {
    function balanceOf(address owner) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

contract LiquidityProtectionTrap is Trap {
    
    // Hardcoded configuration (replace with your actual addresses)
    address constant MONITORED_USER = 0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb; // Replace with actual user
    address constant LIQUIDITY_POOL = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc; // Replace with actual pool
    
    // Events to monitor (optional - reserves can be read directly too)
    string constant SYNC_SIGNATURE = "Sync(uint112,uint112)";
    
    // Threshold: 50% drop = 5000 basis points
    uint256 constant DROP_THRESHOLD = 5000;
    uint256 constant BASIS_POINTS = 10000;
    
    /**
     * @notice Define event filters for reserve monitoring
     * @dev Optional - we read reserves on-chain, but events can provide historical context
     */
    function eventLogFilters() public pure override returns (EventFilter[] memory) {
        EventFilter[] memory filters = new EventFilter[](1);
        
        // Monitor reserve updates (optional)
        filters[0] = EventFilter({
            contractAddress: LIQUIDITY_POOL,
            signature: SYNC_SIGNATURE
        });
        
        return filters;
    }
    
    /**
     * @notice Collect current state by reading on-chain data
     * @dev Uses direct balance reads for accuracy, not event deltas
     * @return Encoded state: (userLPBalance, totalSupply, reserve0, reserve1, timestamp, user, pool)
     */
    function collect() external view override returns (bytes memory) {
        IUniswapV2Pair pair = IUniswapV2Pair(LIQUIDITY_POOL);
        
        uint256 userLP = 0;
        uint256 totalSupply = 0;
        uint112 reserve0 = 0;
        uint112 reserve1 = 0;
        
        // Try/catch for planner-safety - won't revert if contract doesn't exist
        try pair.balanceOf(MONITORED_USER) returns (uint256 balance) {
            userLP = balance;
        } catch {}
        
        try pair.totalSupply() returns (uint256 supply) {
            totalSupply = supply;
        } catch {}
        
        try pair.getReserves() returns (uint112 r0, uint112 r1, uint32) {
            reserve0 = r0;
            reserve1 = r1;
        } catch {}
        
        // Return: userLPBalance, totalSupply, reserve0, reserve1, timestamp, user, pool
        return abi.encode(
            userLP,
            totalSupply,
            reserve0,
            reserve1,
            block.timestamp,
            MONITORED_USER,
            LIQUIDITY_POOL
        );
    }
    
    /**
     * @notice Compare states to detect significant position drops
     * @dev Checks both LP balance drop and reserve drops (rug pull indicator)
     * @param data Array of historical samples [current, previous, ...]
     * @return shouldRespond True if action needed
     * @return responseData Encoded (pool, amount) for responder
     */
    function shouldRespond(bytes[] calldata data) external pure override returns (bool, bytes memory) {
        // Guard against insufficient or empty data
        if (data.length < 2 || data[0].length == 0 || data[1].length == 0) {
            return (false, "");
        }
        
        // Decode current state (data[0] = most recent)
        (
            uint256 currentLPBalance,
            uint256 currentTotalSupply,
            uint112 currentReserve0,
            uint112 currentReserve1,
            ,
            address monitoredUser,
            address liquidityPool
        ) = abi.decode(data[0], (uint256, uint256, uint112, uint112, uint256, address, address));
        
        // Decode previous state (data[1] = one sample ago)
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
                // Trigger withdrawal: (pair, amount=0 means "withdraw all")
                return (
                    true,
                    abi.encode(liquidityPool, uint256(0))
                );
            }
        }
        
        // Check for significant reserve drops (rug pull indicator)
        if (prevReserve0 > 0 && prevReserve1 > 0) {
            // Calculate reserve0 drop percentage
            uint256 reserve0Drop = 0;
            if (currentReserve0 < prevReserve0) {
                reserve0Drop = ((uint256(prevReserve0) - uint256(currentReserve0)) * BASIS_POINTS) / uint256(prevReserve0);
            }
            
            // Calculate reserve1 drop percentage
            uint256 reserve1Drop = 0;
            if (currentReserve1 < prevReserve1) {
                reserve1Drop = ((uint256(prevReserve1) - uint256(currentReserve1)) * BASIS_POINTS) / uint256(prevReserve1);
            }
            
            // Trigger if either reserve drops by 50%+
            if (reserve0Drop >= DROP_THRESHOLD || reserve1Drop >= DROP_THRESHOLD) {
                // Emergency withdrawal on significant reserve drop
                return (
                    true,
                    abi.encode(liquidityPool, uint256(0))
                );
            }
        }
        
        return (false, "");
    }
}
