// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import "../src/LiquidityProtectionTrap.sol";
import "../src/LiquidityWithdrawer.sol";

contract LiquidityProtectionTrapTest is Test {
    LiquidityProtectionTrap public trap;
    LiquidityWithdrawer public withdrawer;
    
    address public constant MONITORED_USER = 0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb;
    address public constant LIQUIDITY_POOL = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
    address public droseraResponse = address(0x9999);
    
    function setUp() public {
        trap = new LiquidityProtectionTrap();
        withdrawer = new LiquidityWithdrawer(droseraResponse);
    }
    
    function test_EventLogFilters() public {
        EventFilter[] memory filters = trap.eventLogFilters();
        assertEq(filters.length, 1, "Should have 1 event filter");
        
        assertEq(filters[0].contractAddress, LIQUIDITY_POOL, "Filter should monitor liquidity pool");
        assertEq(filters[0].signature, "Sync(uint112,uint112)", "Filter should be for Sync events");
    }
    
    function test_Collect_ReturnsCorrectStructure() public {
        bytes memory data = trap.collect();
        
        // Decode to verify structure (7 values)
        (
            uint256 userLPBalance,
            uint256 totalSupply,
            uint112 reserve0,
            uint112 reserve1,
            uint256 timestamp,
            address user,
            address pool
        ) = abi.decode(data, (uint256, uint256, uint112, uint112, uint256, address, address));
        
        // Verify addresses are correct
        assertEq(user, MONITORED_USER, "Should return monitored user");
        assertEq(pool, LIQUIDITY_POOL, "Should return liquidity pool");
        assertGt(timestamp, 0, "Timestamp should be set");
        
        // Note: userLPBalance, totalSupply, reserves will be 0 in test environment
        // unless you mock the pair contract
    }
    
    function test_ShouldRespond_InsufficientData() public {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(
            uint256(100), uint256(1000), 
            uint112(5000), uint112(10000), 
            block.timestamp, MONITORED_USER, LIQUIDITY_POOL
        );
        
        (bool shouldRespond, ) = trap.shouldRespond(data);
        assertFalse(shouldRespond, "Should not respond with insufficient data");
    }
    
    function test_ShouldRespond_EmptyData() public {
        bytes[] memory data = new bytes[](2);
        data[0] = "";  // Empty current
        data[1] = abi.encode(
            uint256(100), uint256(1000), 
            uint112(5000), uint112(10000), 
            block.timestamp, MONITORED_USER, LIQUIDITY_POOL
        );
        
        (bool shouldRespond, ) = trap.shouldRespond(data);
        assertFalse(shouldRespond, "Should not respond with empty data");
    }
    
    function test_ShouldRespond_SignificantLPBalanceDrop() public {
        bytes[] memory data = new bytes[](2);
        
        // Previous state: 1000 LP tokens
        data[1] = abi.encode(
            uint256(1000),    // userLPBalance
            uint256(10000),   // totalSupply
            uint112(50000),   // reserve0
            uint112(100000),  // reserve1
            block.timestamp - 100,
            MONITORED_USER,
            LIQUIDITY_POOL
        );
        
        // Current state: 400 LP tokens (60% drop)
        data[0] = abi.encode(
            uint256(400),     // userLPBalance - 60% drop!
            uint256(10000),   // totalSupply (unchanged)
            uint112(50000),   // reserve0 (unchanged)
            uint112(100000),  // reserve1 (unchanged)
            block.timestamp,
            MONITORED_USER,
            LIQUIDITY_POOL
        );
        
        (bool shouldRespond, bytes memory responseData) = trap.shouldRespond(data);
        
        assertTrue(shouldRespond, "Should respond to 60% LP balance drop");
        
        // Verify response payload
        (address pool, uint256 amount) = abi.decode(responseData, (address, uint256));
        assertEq(pool, LIQUIDITY_POOL, "Response should include pool address");
        assertEq(amount, 0, "Amount 0 means withdraw all");
    }
    
    function test_ShouldNotRespond_SmallLPBalanceDrop() public {
        bytes[] memory data = new bytes[](2);
        
        // Previous state: 1000 LP tokens
        data[1] = abi.encode(
            uint256(1000),
            uint256(10000),
            uint112(50000),
            uint112(100000),
            block.timestamp - 100,
            MONITORED_USER,
            LIQUIDITY_POOL
        );
        
        // Current state: 800 LP tokens (20% drop - below threshold)
        data[0] = abi.encode(
            uint256(800),
            uint256(10000),
            uint112(50000),
            uint112(100000),
            block.timestamp,
            MONITORED_USER,
            LIQUIDITY_POOL
        );
        
        (bool shouldRespond, ) = trap.shouldRespond(data);
        
        assertFalse(shouldRespond, "Should not respond to 20% drop (below 50% threshold)");
    }
    
    function test_ShouldRespond_SignificantReserve0Drop() public {
        bytes[] memory data = new bytes[](2);
        
        // Previous state: Normal reserves
        data[1] = abi.encode(
            uint256(1000),
            uint256(10000),
            uint112(100000),  // reserve0
            uint112(200000),  // reserve1
            block.timestamp - 100,
            MONITORED_USER,
            LIQUIDITY_POOL
        );
        
        // Current state: reserve0 dropped 60% (rug pull!)
        data[0] = abi.encode(
            uint256(1000),    // LP balance unchanged
            uint256(10000),
            uint112(40000),   // reserve0 dropped to 40% of original
            uint112(200000),  // reserve1 unchanged
            block.timestamp,
            MONITORED_USER,
            LIQUIDITY_POOL
        );
        
        (bool shouldRespond, bytes memory responseData) = trap.shouldRespond(data);
        
        assertTrue(shouldRespond, "Should respond to 60% reserve0 drop (rug pull)");
        
        (address pool, uint256 amount) = abi.decode(responseData, (address, uint256));
        assertEq(pool, LIQUIDITY_POOL);
        assertEq(amount, 0);
    }
    
    function test_ShouldRespond_SignificantReserve1Drop() public {
        bytes[] memory data = new bytes[](2);
        
        // Previous state: Normal reserves
        data[1] = abi.encode(
            uint256(1000),
            uint256(10000),
            uint112(100000),
            uint112(200000),  // reserve1
            block.timestamp - 100,
            MONITORED_USER,
            LIQUIDITY_POOL
        );
        
        // Current state: reserve1 dropped 60%
        data[0] = abi.encode(
            uint256(1000),
            uint256(10000),
            uint112(100000),  // reserve0 unchanged
            uint112(80000),   // reserve1 dropped to 40% of original
            block.timestamp,
            MONITORED_USER,
            LIQUIDITY_POOL
        );
        
        (bool shouldRespond, ) = trap.shouldRespond(data);
        
        assertTrue(shouldRespond, "Should respond to 60% reserve1 drop");
    }
    
    function test_ShouldNotRespond_NormalActivity() public {
        bytes[] memory data = new bytes[](2);
        
        // Previous state
        data[1] = abi.encode(
            uint256(1000),
            uint256(10000),
            uint112(100000),
            uint112(200000),
            block.timestamp - 100,
            MONITORED_USER,
            LIQUIDITY_POOL
        );
        
        // Current state: Small changes, all within threshold
        data[0] = abi.encode(
            uint256(980),     // 2% drop - OK
            uint256(10000),
            uint112(95000),   // 5% drop - OK
            uint112(195000),  // 2.5% drop - OK
            block.timestamp,
            MONITORED_USER,
            LIQUIDITY_POOL
        );
        
        (bool shouldRespond, ) = trap.shouldRespond(data);
        
        assertFalse(shouldRespond, "Should not respond to normal market activity");
    }
    
    function test_WithdrawerSetup() public {
        assertEq(withdrawer.owner(), address(this), "Withdrawer owner should be deployer");
        assertEq(withdrawer.droseraResponse(), droseraResponse, "Drosera response should be set");
        assertFalse(withdrawer.paused(), "Should not be paused initially");
    }
    
    function test_WithdrawerPause() public {
        withdrawer.setPaused(true);
        assertTrue(withdrawer.paused(), "Should be paused");
        
        withdrawer.setPaused(false);
        assertFalse(withdrawer.paused(), "Should be unpaused");
    }
    
    function test_WithdrawerOwnershipTransfer() public {
        address newOwner = address(0x5555);
        
        withdrawer.transferOwnership(newOwner);
        assertEq(withdrawer.owner(), newOwner, "Ownership should be transferred");
    }
}
