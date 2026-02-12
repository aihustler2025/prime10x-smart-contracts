// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/Prime10XMarketingVault.sol";
import "./mocks/MockTENX.sol";

contract Prime10XMarketingVaultTest is Test {
    Prime10XMarketingVault public vault;
    MockTENX public tenx;
    address public owner;
    address public alice;
    address public bob;
    address public distributor;
    address public emergencyAdmin;

    event Locked(address indexed user, uint256 amount, uint256 indexed seasonId);
    event Claimed(address indexed user, uint256 amount);
    event ClaimEnableDateSet(uint256 claimEnableDate);
    event DistributorUpdated(address indexed account, bool isDistributor);
    event EmergencyAdminUpdated(address admin);
    event TokenAddressSet(address token);
    event TokensDeposited(address indexed depositor, uint256 amount);

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        distributor = makeAddr("distributor");
        emergencyAdmin = makeAddr("emergencyAdmin");

        tenx = new MockTENX();
        vault = new Prime10XMarketingVault(address(tenx));

        // Fund vault with tokens
        tenx.mint(address(vault), 1_000_000 ether);
    }

    // ------------------------------------------------------------------
    // Deploy
    // ------------------------------------------------------------------

    function test_constructor() public view {
        assertEq(address(vault.tenxToken()), address(tenx));
        assertEq(vault.owner(), owner);
    }

    function test_constructor_allowsZeroToken() public {
        Prime10XMarketingVault v = new Prime10XMarketingVault(address(0));
        assertEq(address(v.tenxToken()), address(0));
    }

    // ------------------------------------------------------------------
    // Claim Enable Date
    // ------------------------------------------------------------------

    function test_setClaimEnableDate() public {
        uint256 claimDate = block.timestamp + 30 days;

        vm.expectEmit(false, false, false, true);
        emit ClaimEnableDateSet(claimDate);

        vault.setClaimEnableDate(claimDate);

        assertEq(vault.claimEnableDate(), claimDate);
        assertTrue(vault.claimEnableDateSet());
    }

    function test_setClaimEnableDate_canUpdate() public {
        uint256 date1 = block.timestamp + 30 days;
        vault.setClaimEnableDate(date1);
        assertEq(vault.claimEnableDate(), date1);

        uint256 date2 = block.timestamp + 60 days;
        vault.setClaimEnableDate(date2);
        assertEq(vault.claimEnableDate(), date2);
        assertTrue(vault.claimEnableDateSet());
    }

    function test_setClaimEnableDate_revert_zeroDate() public {
        vm.expectRevert("MarketingVault: invalid date");
        vault.setClaimEnableDate(0);
    }

    function test_setClaimEnableDate_revert_nonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setClaimEnableDate(block.timestamp + 30 days);
    }

    // ------------------------------------------------------------------
    // Token Address (one-shot setter)
    // ------------------------------------------------------------------

    function test_setTokenAddress_success() public {
        Prime10XMarketingVault v = new Prime10XMarketingVault(address(0));
        MockTENX newToken = new MockTENX();

        vm.expectEmit(false, false, false, true);
        emit TokenAddressSet(address(newToken));

        v.setTokenAddress(address(newToken));
        assertEq(address(v.tenxToken()), address(newToken));
    }

    function test_setTokenAddress_revert_alreadySet() public {
        vm.expectRevert("MarketingVault: token already set");
        vault.setTokenAddress(address(tenx));
    }

    function test_setTokenAddress_revert_zeroAddress() public {
        Prime10XMarketingVault v = new Prime10XMarketingVault(address(0));
        vm.expectRevert("MarketingVault: invalid token");
        v.setTokenAddress(address(0));
    }

    function test_setTokenAddress_revert_nonOwner() public {
        Prime10XMarketingVault v = new Prime10XMarketingVault(address(0));
        vm.prank(alice);
        vm.expectRevert();
        v.setTokenAddress(address(tenx));
    }

    // ------------------------------------------------------------------
    // Emergency Admin
    // ------------------------------------------------------------------

    function test_setEmergencyAdmin_success() public {
        vm.expectEmit(false, false, false, true);
        emit EmergencyAdminUpdated(emergencyAdmin);

        vault.setEmergencyAdmin(emergencyAdmin);
    }

    function test_setEmergencyAdmin_revert_nonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setEmergencyAdmin(emergencyAdmin);
    }

    function test_emergencyUpdateClaimDate_success() public {
        vault.setEmergencyAdmin(emergencyAdmin);

        uint256 newDate = block.timestamp + 90 days;

        vm.expectEmit(false, false, false, true);
        emit ClaimEnableDateSet(newDate);

        vm.prank(emergencyAdmin);
        vault.emergencyUpdateClaimDate(newDate);

        assertEq(vault.claimEnableDate(), newDate);
        assertTrue(vault.claimEnableDateSet());
    }

    function test_emergencyUpdateClaimDate_revert_nonAdmin() public {
        vault.setEmergencyAdmin(emergencyAdmin);

        vm.prank(alice);
        vm.expectRevert("MarketingVault: not emergency admin");
        vault.emergencyUpdateClaimDate(block.timestamp + 90 days);
    }

    function test_emergencyUpdateClaimDate_revert_zeroDate() public {
        vault.setEmergencyAdmin(emergencyAdmin);

        vm.prank(emergencyAdmin);
        vm.expectRevert("MarketingVault: invalid date");
        vault.emergencyUpdateClaimDate(0);
    }

    // ------------------------------------------------------------------
    // Distributors
    // ------------------------------------------------------------------

    function test_setDistributor_grant() public {
        vm.expectEmit(true, false, false, true);
        emit DistributorUpdated(distributor, true);

        vault.setDistributor(distributor, true);
    }

    function test_setDistributor_revoke() public {
        vault.setDistributor(distributor, true);
        vault.setDistributor(distributor, false);
    }

    function test_setDistributor_revert_zeroAddress() public {
        vm.expectRevert("MarketingVault: invalid user");
        vault.setDistributor(address(0), true);
    }

    function test_setDistributor_revert_nonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setDistributor(distributor, true);
    }

    // ------------------------------------------------------------------
    // Allocation
    // ------------------------------------------------------------------

    function test_allocateLockedTokens() public {
        vm.expectEmit(true, false, true, true);
        emit Locked(alice, 100 ether, 1);

        vault.allocateLockedTokens(alice, 100 ether, 1);

        assertEq(vault.totalLockedOf(alice), 100 ether);
        assertEq(vault.lockedBySeason(alice, 1), 100 ether);
        assertEq(vault.seasonTotalLocked(1), 100 ether);
    }

    function test_allocate_distributorCanAllocate() public {
        vault.setDistributor(distributor, true);

        vm.prank(distributor);
        vault.allocateLockedTokens(alice, 100 ether, 1);

        assertEq(vault.totalLockedOf(alice), 100 ether);
    }

    function test_batchAllocate() public {
        address[] memory users = new address[](2);
        users[0] = alice;
        users[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100 ether;
        amounts[1] = 200 ether;

        vault.batchAllocateLockedTokens(users, amounts, 1);

        assertEq(vault.totalLockedOf(alice), 100 ether);
        assertEq(vault.totalLockedOf(bob), 200 ether);
        assertEq(vault.seasonTotalLocked(1), 300 ether);
    }

    function test_batchAllocate_revert_lengthMismatch() public {
        address[] memory users = new address[](2);
        users[0] = alice;
        users[1] = bob;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;

        vm.expectRevert("MarketingVault: length mismatch");
        vault.batchAllocateLockedTokens(users, amounts, 1);
    }

    function test_allocate_revert_unauthorized() public {
        vm.prank(alice);
        vm.expectRevert("MarketingVault: not authorized");
        vault.allocateLockedTokens(alice, 100 ether, 1);
    }

    function test_allocate_revert_zeroAddress() public {
        vm.expectRevert("MarketingVault: invalid user");
        vault.allocateLockedTokens(address(0), 100 ether, 1);
    }

    function test_allocate_revert_zeroAmount() public {
        vm.expectRevert("MarketingVault: invalid amount");
        vault.allocateLockedTokens(alice, 0, 1);
    }

    function test_allocate_revert_zeroSeason() public {
        vm.expectRevert("MarketingVault: invalid season");
        vault.allocateLockedTokens(alice, 100 ether, 0);
    }

    function test_allocate_revert_tokenNotSet() public {
        Prime10XMarketingVault v = new Prime10XMarketingVault(address(0));
        vm.expectRevert("MarketingVault: token not set");
        v.allocateLockedTokens(alice, 100 ether, 1);
    }

    // ------------------------------------------------------------------
    // Claim
    // ------------------------------------------------------------------

    function test_claim_success() public {
        vault.allocateLockedTokens(alice, 100 ether, 1);

        uint256 claimDate = block.timestamp + 1;
        vault.setClaimEnableDate(claimDate);
        vm.warp(claimDate);

        vm.expectEmit(true, false, false, true);
        emit Claimed(alice, 100 ether);

        vm.prank(alice);
        vault.claim();

        assertEq(tenx.balanceOf(alice), 100 ether);
        assertEq(vault.totalLockedOf(alice), 0);
        assertEq(vault.totalClaimedOf(alice), 100 ether);
    }

    function test_claim_revert_beforeClaimDate() public {
        vault.allocateLockedTokens(alice, 100 ether, 1);
        uint256 claimDate = block.timestamp + 1 days;
        vault.setClaimEnableDate(claimDate);
        vm.warp(claimDate - 1);

        vm.prank(alice);
        vm.expectRevert("MarketingVault: claims not enabled");
        vault.claim();
    }

    function test_claim_revert_claimDateNotSet() public {
        vault.allocateLockedTokens(alice, 100 ether, 1);

        vm.prank(alice);
        vm.expectRevert("MarketingVault: claims not enabled");
        vault.claim();
    }

    function test_claim_revert_nothingToClaim() public {
        uint256 claimDate = block.timestamp + 1;
        vault.setClaimEnableDate(claimDate);
        vm.warp(claimDate);

        vm.prank(alice);
        vm.expectRevert("MarketingVault: nothing to claim");
        vault.claim();
    }

    // ------------------------------------------------------------------
    // ClaimFor
    // ------------------------------------------------------------------

    function test_claimFor_ownerCanClaim() public {
        vault.allocateLockedTokens(alice, 100 ether, 1);
        uint256 claimDate = block.timestamp + 1;
        vault.setClaimEnableDate(claimDate);
        vm.warp(claimDate);

        vault.claimFor(alice);

        assertEq(tenx.balanceOf(alice), 100 ether);
    }

    function test_claimFor_revert_nonOwner() public {
        vault.allocateLockedTokens(alice, 100 ether, 1);
        uint256 claimDate = block.timestamp + 1;
        vault.setClaimEnableDate(claimDate);
        vm.warp(claimDate);

        vm.prank(bob);
        vm.expectRevert();
        vault.claimFor(alice);
    }

    // ------------------------------------------------------------------
    // Deposit
    // ------------------------------------------------------------------

    function test_depositTokens() public {
        tenx.mint(alice, 500 ether);

        vm.startPrank(alice);
        tenx.approve(address(vault), 500 ether);

        vm.expectEmit(true, false, false, true);
        emit TokensDeposited(alice, 500 ether);

        vault.depositTokens(500 ether);
        vm.stopPrank();

        assertEq(vault.vaultBalance(), 1_000_500 ether);
    }

    function test_depositTokens_revert_zeroAmount() public {
        vm.expectRevert("MarketingVault: invalid amount");
        vault.depositTokens(0);
    }

    function test_depositTokens_revert_tokenNotSet() public {
        Prime10XMarketingVault v = new Prime10XMarketingVault(address(0));
        vm.expectRevert("MarketingVault: token not set");
        v.depositTokens(100 ether);
    }

    // ------------------------------------------------------------------
    // Rescue
    // ------------------------------------------------------------------

    function test_rescueTokens_nonTENX() public {
        MockTENX otherToken = new MockTENX();
        otherToken.mint(address(vault), 500 ether);

        vault.rescueTokens(address(otherToken), alice, 500 ether);
        assertEq(otherToken.balanceOf(alice), 500 ether);
    }

    function test_rescueTokens_tenxSurplus() public {
        vault.allocateLockedTokens(alice, 100 ether, 1);

        // Vault has 1M, only 100 locked — can rescue surplus
        vault.rescueTokens(address(tenx), owner, 999_900 ether);
        assertEq(tenx.balanceOf(address(vault)), 100 ether);
    }

    function test_rescueTokens_revert_tenxBelowLocked() public {
        vault.allocateLockedTokens(alice, 100 ether, 1);

        vm.expectRevert("MarketingVault: insufficient TENX balance");
        vault.rescueTokens(address(tenx), owner, 999_901 ether);
    }

    function test_rescueTokens_revert_zeroRecipient() public {
        vm.expectRevert("MarketingVault: invalid user");
        vault.rescueTokens(address(tenx), address(0), 100 ether);
    }

    // ------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------

    function test_isClaimEnabled() public {
        assertFalse(vault.isClaimEnabled());

        uint256 claimDate = block.timestamp + 1 days;
        vault.setClaimEnableDate(claimDate);
        assertFalse(vault.isClaimEnabled());

        vm.warp(claimDate);
        assertTrue(vault.isClaimEnabled());
    }

    function test_vaultBalance() public view {
        assertEq(vault.vaultBalance(), 1_000_000 ether);
    }

    // ------------------------------------------------------------------
    // Allocation accumulation
    // ------------------------------------------------------------------

    function test_allocate_sameUserSameSeason_accumulates() public {
        vault.allocateLockedTokens(alice, 100 ether, 1);
        vault.allocateLockedTokens(alice, 50 ether, 1);

        assertEq(vault.totalLockedOf(alice), 150 ether);
        assertEq(vault.lockedBySeason(alice, 1), 150 ether);
        assertEq(vault.seasonTotalLocked(1), 150 ether);
    }

    function test_allocate_multipleSeasons_thenClaimPullsAll() public {
        vault.allocateLockedTokens(alice, 100 ether, 1);
        vault.allocateLockedTokens(alice, 200 ether, 2);

        uint256 claimDate = block.timestamp + 1;
        vault.setClaimEnableDate(claimDate);
        vm.warp(claimDate);

        vm.prank(alice);
        vault.claim();

        assertEq(tenx.balanceOf(alice), 300 ether);
        assertEq(vault.totalLockedOf(alice), 0);
        assertEq(vault.totalClaimedOf(alice), 300 ether);
    }

    function test_batchAllocate_singleItem() public {
        address[] memory users = new address[](1);
        users[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 ether;

        vault.batchAllocateLockedTokens(users, amounts, 1);
        assertEq(vault.totalLockedOf(alice), 100 ether);
    }

    function test_batchAllocate_emptyArrays() public {
        address[] memory users = new address[](0);
        uint256[] memory amounts = new uint256[](0);

        vault.batchAllocateLockedTokens(users, amounts, 1);
        // no-op, no revert
    }

    function test_allocate_revokedDistributor_reverts() public {
        vault.setDistributor(distributor, true);
        vault.setDistributor(distributor, false);

        vm.prank(distributor);
        vm.expectRevert("MarketingVault: not authorized");
        vault.allocateLockedTokens(alice, 100 ether, 1);
    }

    // ------------------------------------------------------------------
    // Claiming boundaries
    // ------------------------------------------------------------------

    function test_claim_atExactClaimDate() public {
        vault.allocateLockedTokens(alice, 100 ether, 1);
        uint256 claimDate = block.timestamp + 1;
        vault.setClaimEnableDate(claimDate);
        vm.warp(claimDate); // exactly at boundary (>=)

        vm.prank(alice);
        vault.claim();
        assertEq(tenx.balanceOf(alice), 100 ether);
    }

    function test_claim_oneSecondBeforeClaimDate_reverts() public {
        vault.allocateLockedTokens(alice, 100 ether, 1);
        uint256 claimDate = block.timestamp + 1 days;
        vault.setClaimEnableDate(claimDate);
        vm.warp(claimDate - 1);

        vm.prank(alice);
        vm.expectRevert("MarketingVault: claims not enabled");
        vault.claim();
    }

    function test_claim_multipleUsersSequential_globalLockedCorrect() public {
        vault.allocateLockedTokens(alice, 100 ether, 1);
        vault.allocateLockedTokens(bob, 200 ether, 1);

        uint256 claimDate = block.timestamp + 1;
        vault.setClaimEnableDate(claimDate);
        vm.warp(claimDate);

        vm.prank(alice);
        vault.claim();

        vm.prank(bob);
        vault.claim();

        assertEq(tenx.balanceOf(alice), 100 ether);
        assertEq(tenx.balanceOf(bob), 200 ether);
        assertEq(vault.totalLockedOf(alice), 0);
        assertEq(vault.totalLockedOf(bob), 0);
    }

    function test_claim_claimedTwice_reverts() public {
        vault.allocateLockedTokens(alice, 100 ether, 1);
        uint256 claimDate = block.timestamp + 1;
        vault.setClaimEnableDate(claimDate);
        vm.warp(claimDate);

        vm.prank(alice);
        vault.claim();

        vm.prank(alice);
        vm.expectRevert("MarketingVault: nothing to claim");
        vault.claim();
    }

    function test_claim_multiSeason_eventAmount() public {
        vault.allocateLockedTokens(alice, 100 ether, 1);
        vault.allocateLockedTokens(alice, 200 ether, 2);

        uint256 claimDate = block.timestamp + 1;
        vault.setClaimEnableDate(claimDate);
        vm.warp(claimDate);

        vm.expectEmit(true, false, false, true);
        emit Claimed(alice, 300 ether);

        vm.prank(alice);
        vault.claim();
    }

    // ------------------------------------------------------------------
    // Access control
    // ------------------------------------------------------------------

    function test_claimFor_distributorCannotClaimFor() public {
        vault.allocateLockedTokens(alice, 100 ether, 1);
        vault.setDistributor(distributor, true);

        uint256 claimDate = block.timestamp + 1;
        vault.setClaimEnableDate(claimDate);
        vm.warp(claimDate);

        vm.prank(distributor);
        vm.expectRevert();
        vault.claimFor(alice);
    }

    function test_claimFor_zeroAddress_reverts() public {
        uint256 claimDate = block.timestamp + 1;
        vault.setClaimEnableDate(claimDate);
        vm.warp(claimDate);

        vm.expectRevert("MarketingVault: nothing to claim");
        vault.claimFor(address(0));
    }

    // ------------------------------------------------------------------
    // Deposits
    // ------------------------------------------------------------------

    function test_deposit_revert_noApproval() public {
        tenx.mint(alice, 500 ether);

        vm.prank(alice);
        vm.expectRevert();
        vault.depositTokens(500 ether);
    }

    function test_deposit_multipleDeposits_accumulates() public {
        tenx.mint(alice, 1000 ether);

        vm.startPrank(alice);
        tenx.approve(address(vault), 1000 ether);
        vault.depositTokens(400 ether);
        vault.depositTokens(600 ether);
        vm.stopPrank();

        assertEq(vault.vaultBalance(), 1_001_000 ether);
    }

    // ------------------------------------------------------------------
    // View defaults
    // ------------------------------------------------------------------

    function test_totalLockedOf_unknownUser_returnsZero() public {
        assertEq(vault.totalLockedOf(makeAddr("unknown")), 0);
    }

    function test_totalClaimedOf_unknownUser_returnsZero() public {
        assertEq(vault.totalClaimedOf(makeAddr("unknown")), 0);
    }

    function test_lockedBySeason_afterClaim_stillShows() public {
        vault.allocateLockedTokens(alice, 100 ether, 1);
        vault.allocateLockedTokens(alice, 200 ether, 2);

        uint256 claimDate = block.timestamp + 1;
        vault.setClaimEnableDate(claimDate);
        vm.warp(claimDate);

        vm.prank(alice);
        vault.claim();

        // totalLocked zeroed but per-season amounts still readable
        assertEq(vault.totalLockedOf(alice), 0);
        assertEq(vault.lockedBySeason(alice, 1), 100 ether);
        assertEq(vault.lockedBySeason(alice, 2), 200 ether);
    }

    function test_seasonTotalLocked_multipleUsers() public {
        vault.allocateLockedTokens(alice, 100 ether, 1);
        vault.allocateLockedTokens(bob, 250 ether, 1);

        assertEq(vault.seasonTotalLocked(1), 350 ether);
    }

    // ------------------------------------------------------------------
    // Rescue extras
    // ------------------------------------------------------------------

    function test_rescueTokens_revert_nonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.rescueTokens(address(tenx), alice, 100 ether);
    }

    function test_rescueTokens_exactSurplus() public {
        vault.allocateLockedTokens(alice, 100 ether, 1);

        // Vault has 1M, 100 locked -> surplus = 999_900
        vault.rescueTokens(address(tenx), owner, 999_900 ether);
        assertEq(tenx.balanceOf(address(vault)), 100 ether);
    }

    function test_rescueTokens_tenxAfterClaim() public {
        vault.allocateLockedTokens(alice, 100 ether, 1);

        uint256 claimDate = block.timestamp + 1;
        vault.setClaimEnableDate(claimDate);
        vm.warp(claimDate);

        vm.prank(alice);
        vault.claim();

        // After claim, globalLocked drops by 100 -> all vault balance is rescuable
        uint256 remaining = tenx.balanceOf(address(vault));
        vault.rescueTokens(address(tenx), owner, remaining);
        assertEq(tenx.balanceOf(address(vault)), 0);
    }

    function test_rescueTokens_zeroAmount() public {
        vault.rescueTokens(address(tenx), owner, 0);
        // No revert for 0 amount — succeeds as no-op transfer
        assertEq(vault.vaultBalance(), 1_000_000 ether);
    }
}
