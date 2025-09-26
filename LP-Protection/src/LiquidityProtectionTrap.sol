// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {EventLog, EventFilter, EventFilterLib} from "drosera-network-contracts/src/libraries/Events.sol";
import {Trap} from "drosera-network-contracts/src/Trap.sol";

/**
 * @title LiquidityProtectionTrap
 * @dev Monitors user's liquidity position and triggers automatic withdrawal 
 *      when position drops by 50% or more from initial deposit
 */
contract LiquidityProtectionTrap is Trap {
    
    // Events we want to monitor
    string constant MINT_SIGNATURE = "Mint(address,uint256,uint256)";
    string constant BURN_SIGNATURE = "Burn(address,uint256,uint256,address)";
    string constant SYNC_SIGNATURE = "Sync(uint112,uint112)";
    
    // Configuration
    address public immutable MONITORED_USER;
    address public immutable LIQUIDITY_POOL;
    
    // Threshold for position drop (50% = 5000 basis points)
    uint256 public constant DROP_THRESHOLD = 5000;
    uint256 public constant BASIS_POINTS = 10000;
    
    constructor(address _monitoredUser, address _liquidityPool) {
        MONITORED_USER = _monitoredUser;
        LIQUIDITY_POOL = _liquidityPool;
    }
    
    function eventLogFilters() public view override returns (EventFilter[] memory) {
        EventFilter[] memory filters = new EventFilter[](3);
        
        filters[0] = EventFilter({
            contractAddress: LIQUIDITY_POOL,
            signature: MINT_SIGNATURE
        });
        
        filters[1] = EventFilter({
            contractAddress: LIQUIDITY_POOL,
            signature: BURN_SIGNATURE
        });
        
        filters[2] = EventFilter({
            contractAddress: LIQUIDITY_POOL,
            signature: SYNC_SIGNATURE
        });
        
        return filters;
    }
    
    function collect() external view override returns (bytes memory) {
        EventLog[] memory logs = getEventLogs();
        
        uint256 totalMints = 0;
        uint256 totalBurns = 0;
        uint112 reserve0 = 0;
        uint112 reserve1 = 0;
        
        // Process event logs
        for (uint256 i = 0; i < logs.length; i++) {
            EventLog memory log = logs[i];
            
            // Skip if not from our monitored pool
            if (log.emitter != LIQUIDITY_POOL) continue;
            
            // Check for Mint events
            if (log.topics.length > 0 && log.topics[0] == keccak256(bytes(MINT_SIGNATURE))) {
                if (log.topics.length >= 2) {
                    address minter = address(uint160(uint256(log.topics[1])));
                    if (minter == MONITORED_USER) {
                        (uint256 amount0, uint256 amount1) = abi.decode(log.data, (uint256, uint256));
                        totalMints += amount0 + amount1;
                    }
                }
            }
            
            // Check for Burn events
            else if (log.topics.length > 0 && log.topics[0] == keccak256(bytes(BURN_SIGNATURE))) {
                if (log.topics.length >= 2) {
                    address burner = address(uint160(uint256(log.topics[1])));
                    if (burner == MONITORED_USER) {
                        (uint256 amount0, uint256 amount1,) = abi.decode(log.data, (uint256, uint256, address));
                        totalBurns += amount0 + amount1;
                    }
                }
            }
            
            // Check for Sync events (reserve updates)
            else if (log.topics.length > 0 && log.topics[0] == keccak256(bytes(SYNC_SIGNATURE))) {
                (reserve0, reserve1) = abi.decode(log.data, (uint112, uint112));
            }
        }
        
        // Include the monitored addresses in the return data so shouldRespond can access them
        return abi.encode(totalMints, totalBurns, reserve0, reserve1, block.timestamp, MONITORED_USER, LIQUIDITY_POOL);
    }
    
    function shouldRespond(bytes[] calldata data) external pure override returns (bool, bytes memory) {
        if (data.length < 2) {
            return (false, "");
        }
        
        // Decode current and previous data (now includes monitored addresses)
        (uint256 currentMints, uint256 currentBurns, uint112 currentReserve0, uint112 currentReserve1,, address monitoredUser, address liquidityPool) = 
            abi.decode(data[0], (uint256, uint256, uint112, uint112, uint256, address, address));
            
        (uint256 prevMints, uint256 prevBurns, uint112 prevReserve0, uint112 prevReserve1,,, ) = 
            abi.decode(data[1], (uint256, uint256, uint112, uint112, uint256, address, address));
        
        // Calculate position change
        uint256 netCurrentPosition = currentMints > currentBurns ? currentMints - currentBurns : 0;
        uint256 netPrevPosition = prevMints > prevBurns ? prevMints - prevBurns : 0;
        
        // Check for significant position drop
        if (netPrevPosition > 0 && netCurrentPosition < netPrevPosition) {
            uint256 positionDrop = netPrevPosition - netCurrentPosition;
            uint256 dropPercentage = (positionDrop * BASIS_POINTS) / netPrevPosition;
            
            if (dropPercentage >= DROP_THRESHOLD) {
                return (
                    true,
                    abi.encode(
                        monitoredUser,
                        liquidityPool,
                        dropPercentage,
                        "Liquidity position dropped by more than 50%"
                    )
                );
            }
        }
        
        // Check for significant reserve drops (indicating potential rug pull)
        if (prevReserve0 > 0 && prevReserve1 > 0) {
            uint256 reserve0Drop = prevReserve0 > currentReserve0 ? 
                ((prevReserve0 - currentReserve0) * BASIS_POINTS) / prevReserve0 : 0;
            uint256 reserve1Drop = prevReserve1 > currentReserve1 ? 
                ((prevReserve1 - currentReserve1) * BASIS_POINTS) / prevReserve1 : 0;
            
            if (reserve0Drop >= DROP_THRESHOLD || reserve1Drop >= DROP_THRESHOLD) {
                return (
                    true,
                    abi.encode(
                        monitoredUser,
                        liquidityPool,
                        reserve0Drop > reserve1Drop ? reserve0Drop : reserve1Drop,
                        "Significant liquidity pool reserve drop detected"
                    )
                );
            }
        }
        
        return (false, "");
    }
}
