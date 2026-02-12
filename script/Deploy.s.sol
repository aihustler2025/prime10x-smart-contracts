// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../contracts/Prime10XBadgeSBT.sol";
import "../contracts/Prime10XMarketingVault.sol";
import "../contracts/Prime10XRewardVoucher.sol";

/// @title Prime10X Deploy Script
/// @notice Deploys BadgeSBT, MarketingVault (with deferred token), and RewardVoucher.
///         RaffleVault is intentionally skipped.
contract Deploy is Script {
    function run() external {
        vm.startBroadcast();

        Prime10XBadgeSBT badge = new Prime10XBadgeSBT();
        console.log("BadgeSBT deployed at:", address(badge));

        // Deploy vault with address(0) — TENX token will be set later via setTokenAddress()
        Prime10XMarketingVault vault = new Prime10XMarketingVault(address(0));
        console.log("MarketingVault deployed at:", address(vault));

        Prime10XRewardVoucher voucher = new Prime10XRewardVoucher("Prime10X Voucher", "P10X-V");
        console.log("RewardVoucher deployed at:", address(voucher));

        vm.stopBroadcast();
    }
}
