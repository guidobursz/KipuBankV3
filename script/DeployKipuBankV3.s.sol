// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {KipuBankV3} from "../src/KipuBankV3.sol";

contract DeployKipuBankV3 is Script {
    function run() external returns (KipuBankV3) {
        // Addresses para Sepolia
        address USDC_SEPOLIA = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
        address WETH_SEPOLIA = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
        address ROUTER_SEPOLIA = 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008;
        
        uint256 bankCapUSD = 1000 * 10**6;      // $1000
        uint256 umbralRetiroUSD = 100 * 10**6;   // $100
        
        address owner = vm.envAddress("OWNER_ADDRESS");
        
        vm.startBroadcast();
        
        KipuBankV3 banco = new KipuBankV3(
            bankCapUSD,
            umbralRetiroUSD,
            USDC_SEPOLIA,
            WETH_SEPOLIA,
            owner,
            ROUTER_SEPOLIA
        );
        
        vm.stopBroadcast();
        
        return banco;
    }
}