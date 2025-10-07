// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import "../src/LiquidityProtectionTrap.sol";
import "../src/LiquidityWithdrawer.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address droseraResponse = vm.envAddress("DROSERA_RESPONSE_CONTRACT");
        address targetPair = vm.envAddress("TARGET_LP_PAIR");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy the Liquidity Protection Trap
        LiquidityProtectionTrap trap = new LiquidityProtectionTrap(targetPair);
        console.log("LiquidityProtectionTrap deployed at:", address(trap));
        
        // Deploy the Liquidity Withdrawer (optional)
        LiquidityWithdrawer withdrawer = new LiquidityWithdrawer(droseraResponse);
        console.log("LiquidityWithdrawer deployed at:", address(withdrawer));
        
        vm.stopBroadcast();
        
        // Log deployment info for drosera.toml
        console.log("===============================================");
        console.log("Add this to your drosera.toml:");
        console.log("[deployment]");
        console.log("address = \"%s\"", address(trap));
        console.log("===============================================");
    }
}
