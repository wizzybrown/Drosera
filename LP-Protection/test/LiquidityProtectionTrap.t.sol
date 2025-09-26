// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import "../src/LiquidityProtectionTrap.sol";
import "../src/LiquidityWithdrawer.sol";
import {EventLog, EventFilter} from "drosera-network-contracts/src/libraries/Events.sol";

contract LiquidityProtectionTrapTest is Test {
    LiquidityProtectionTrap public trap;
    LiquidityWithdrawer public withdrawer;
    
    address public monitoredUser = address(0x1234);
    address public liquidityPool = address(0x5678);
    address public droseraResponse = address(0x9999);
    
    function setUp() public {
        trap = new LiquidityProtectionTrap(monitoredUser, liquidityPool);
        withdrawer = new LiquidityWithdrawer(droseraResponse);
    }
    
    function test_Constructor() public {
        assertEq(trap.MONITORED_USER(), monitoredUser, "Monitored user should be set correctly");
        assertEq(trap.LIQUIDITY_POOL(), liquidityPool, "Liquidity pool should be set correctly");
        assertEq(withdrawer.owner(), address(this), "Withdrawer owner should be deployer");
        assertEq(withdrawer.droseraResponse(), droseraResponse, "Drosera response should be set correctly");
    }
    
    function test_EventLogFilters() public {
        EventFilter[] memory filters = trap.eventLogFilters();
        assertEq(filters.length, 3, "Should have 3 event filters");
        
        assertEq(filters[0].contractAddress, liquidityPool, "First filter should monitor liquidity pool");
        assertEq(filters[0].signature, "Mint(address,uint256,uint256)", "First filter should be for Mint events");
        
        assertEq(filters[1].contractAddress, liquidityPool, "Second filter should monitor liquidity pool");
        assertEq(filters[1].signature, "Burn(address,uint256,uint256,address)", "Second filter should be for Burn events");
        
        assertEq(filters[2].contractAddress, liquidityPool, "Third filter should monitor liquidity pool");
        assertEq(filters[2].signature, "Sync(uint112,uint112)", "Third filter should be for Sync events");
    }
    
    function test_Collect_EmptyLogs() public {
        bytes memory data = trap.collect();
        (uint256 totalMints, uint256 totalBurns, uint112 reserve0, uint112 reserve1, uint256 timestamp) = 
            abi.decode(data, (uint256, uint256, uint112, uint112, uint256));
        
        assertEq(totalMints, 0, "Total mints should be 0 with no logs");
        assertEq(totalBurns, 0, "Total burns should be 0 with no logs");
        assertEq(reserve0, 0, "Reserve0 should be 0 with no logs");
        assertEq(reserve1, 0, "Reserve1 should be 0 with no logs");
        assertGt(timestamp, 0, "Timestamp should be set");
    }
    
    function test_ShouldRespond_InsufficientData() public {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encode(uint256(100), uint256(50), uint112(1000), uint112(2000), block.timestamp);
        
        (bool shouldRespond, ) = trap.shouldRespond(data);
        assertFalse(shouldRespond, "Should not respond with insufficient data");
    }
    
    function test_ShouldRespond_SignificantDrop() public {
        bytes[] memory data = new bytes[](2);
        
        // Previous state: 1000 mints, 0 burns (net position: 1000)
        data[1] = abi.encode(uint256(1000), uint256(0), uint112(5000), uint112(10000), block.timestamp);
        
        // Current state: 1000 mints, 600 burns (net position: 400, which is 60% drop)
        data[0] = abi.encode(uint256(1000), uint256(600), uint112(3000), uint112(6000), block.timestamp);
        
        (bool shouldRespond, bytes memory responseData) = trap.shouldRespond(data);
        
        assertTrue(shouldRespond, "Should respond to significant position drop");
        
        (address user, address pool, uint256 dropPercentage, string memory message) = 
            abi.decode(responseData, (address, address, uint256, string));
        
        assertEq(user, monitoredUser, "Response should include monitored user");
        assertEq(pool, liquidityPool, "Response should include liquidity pool");
        assertGe(dropPercentage, 5000, "Drop percentage should be at least 50%");
        assertTrue(bytes(message).length > 0, "Response should include message");
    }
    
    function test_ShouldNotRespond_SmallDrop() public {
        bytes[] memory data = new bytes[](2);
        
        // Previous state: 1000 mints, 0 burns (net position: 1000)
        data[1] = abi.encode(uint256(1000), uint256(0), uint112(5000), uint112(10000), block.timestamp);
        
        // Current state: 1000 mints, 200 burns (net position: 800, which is 20% drop)
        data[0] = abi.encode(uint256(1000), uint256(200), uint112(4000), uint112(8000), block.timestamp);
        
        (bool shouldRespond, ) = trap.shouldRespond(data);
        
        assertFalse(shouldRespond, "Should not respond to small position drop");
    }
    
    function test_WithdrawerPause() public {
        assertFalse(withdrawer.paused(), "Should not be paused initially");
        
        withdrawer.setPaused(true);
        assertTrue(withdrawer.paused(), "Should be paused after setting");
        
        withdrawer.setPaused(false);
        assertFalse(withdrawer.paused(), "Should not be paused after unsetting");
    }
    
    function test_WithdrawerOwnership() public {
        address newOwner = address(0x5555);
        
        withdrawer.transferOwnership(newOwner);
        assertEq(withdrawer.owner(), newOwner, "Ownership should be transferred");
    }
}
