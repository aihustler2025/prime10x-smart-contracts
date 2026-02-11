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

    event Locked(address indexed user, uint256 amount, uint256 indexed seasonId);
    event Claimed(address indexed user, uint256 amount);
    event TGETimestampSet(uint256 tgeTimestamp);
    event DistributorUpdated(address indexed account, bool isDistributor);
    event LockEnforcedUpdated(bool enforced);
    event TokensDeposited(address indexed depositor, uint256 amount);

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        distributor = makeAddr("distributor");

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

    function test_constructor_revert_zeroAddress() public {
        vm.expectRevert("MarketingVault: invalid token");
        new Prime10XMarketingVault(address(0));
    }

    // ------------------------------------------------------------------
    // TGE
    // ------------------------------------------------------------------

    function test_setTGE() public {
        uint256 tge = block.timestamp + 1 days;

        vm.expectEmit(false, false, false, true);
        emit TGETimestampSet(tge);

        vault.setTGETimestamp(tge);

        assertEq(vault.tgeTimestamp(), tge);
        assertTrue(vault.tgeSet());
    }

    function test_setTGE_canUpdate() public {
        uint256 tge1 = block.timestamp + 1 days;
        vault.setTGETimestamp(tge1);
        assertEq(vault.tgeTimestamp(), tge1);

        uint256 tge2 = block.timestamp + 2 days;
        vault.setTGETimestamp(tge2);
        assertEq(vault.tgeTimestamp(), tge2);
        assertTrue(vault.tgeSet());
    }

    function test_setTGE_revert_pastTimestamp() public {
        vm.expectRevert("MarketingVault: TGE must be in future");
        vault.setTGETimestamp(block.timestamp - 1);
    }

    function test_setTGE_revert_nonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setTGETimestamp(block.timestamp + 1 days);
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

    // ------------------------------------------------------------------
    // Claim
    // ------------------------------------------------------------------

    function test_claim_success() public {
        vault.allocateLockedTokens(alice, 100 ether, 1);

        // Set TGE and warp past lock
        uint256 tge = block.timestamp + 1;
        vault.setTGETimestamp(tge);
        vm.warp(tge + 365 days);

        vm.expectEmit(true, false, false, true);
        emit Claimed(alice, 100 ether);

        vm.prank(alice);
        vault.claim();

        assertEq(tenx.balanceOf(alice), 100 ether);
        assertEq(vault.totalLockedOf(alice), 0);
        assertEq(vault.totalClaimedOf(alice), 100 ether);
    }

    function test_claim_revert_beforeUnlock() public {
        vault.allocateLockedTokens(alice, 100 ether, 1);
        uint256 tge = block.timestamp + 1;
        vault.setTGETimestamp(tge);
        vm.warp(tge + 364 days);

        vm.prank(alice);
        vm.expectRevert("MarketingVault: not unlocked yet");
        vault.claim();
    }

    function test_claim_revert_tgeNotSet() public {
        vault.allocateLockedTokens(alice, 100 ether, 1);

        vm.prank(alice);
        vm.expectRevert("MarketingVault: not unlocked yet");
        vault.claim();
    }

    function test_claim_revert_nothingToClaim() public {
        uint256 tge = block.timestamp + 1;
        vault.setTGETimestamp(tge);
        vm.warp(tge + 365 days);

        vm.prank(alice);
        vm.expectRevert("MarketingVault: nothing to claim");
        vault.claim();
    }

    // ------------------------------------------------------------------
    // ClaimFor
    // ------------------------------------------------------------------

    function test_claimFor_ownerCanClaim() public {
        vault.allocateLockedTokens(alice, 100 ether, 1);
        uint256 tge = block.timestamp + 1;
        vault.setTGETimestamp(tge);
        vm.warp(tge + 365 days);

        vault.claimFor(alice);

        assertEq(tenx.balanceOf(alice), 100 ether);
    }

    function test_claimFor_revert_nonOwner() public {
        vault.allocateLockedTokens(alice, 100 ether, 1);
        uint256 tge = block.timestamp + 1;
        vault.setTGETimestamp(tge);
        vm.warp(tge + 365 days);

        vm.prank(bob);
        vm.expectRevert();
        vault.claimFor(alice);
    }

    // ------------------------------------------------------------------
    // Lock enforcement
    // ------------------------------------------------------------------

    function test_setLockEnforced_disable() public {
        vm.expectEmit(false, false, false, true);
        emit LockEnforcedUpdated(false);

        vault.setLockEnforced(false);
        assertTrue(vault.isUnlocked());
    }

    function test_setLockEnforced_reEnable() public {
        vault.setLockEnforced(false);
        assertTrue(vault.isUnlocked());

        vault.setLockEnforced(true);
        assertFalse(vault.isUnlocked());
    }

    function test_setLockEnforced_revert_nonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setLockEnforced(false);
    }

    function test_claim_lockDisabled() public {
        vault.allocateLockedTokens(alice, 100 ether, 1);
        vault.setLockEnforced(false);

        vm.prank(alice);
        vault.claim();

        assertEq(tenx.balanceOf(alice), 100 ether);
        assertEq(vault.totalLockedOf(alice), 0);
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

    function test_getUnlockTime_noTGE() public view {
        assertEq(vault.getUnlockTime(), 0);
    }

    function test_getUnlockTime_withTGE() public {
        uint256 tge = block.timestamp + 1 days;
        vault.setTGETimestamp(tge);
        assertEq(vault.getUnlockTime(), tge + 365 days);
    }

    function test_isUnlocked() public {
        assertFalse(vault.isUnlocked());

        uint256 tge = block.timestamp + 1;
        vault.setTGETimestamp(tge);
        assertFalse(vault.isUnlocked());

        vm.warp(tge + 365 days);
        assertTrue(vault.isUnlocked());
    }

    function test_vaultBalance() public view {
        assertEq(vault.vaultBalance(), 1_000_000 ether);
    }

    // ------------------------------------------------------------------
    // NEW: Allocation accumulation
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

        uint256 tge = block.timestamp + 1;
        vault.setTGETimestamp(tge);
        vm.warp(tge + 365 days);

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
    // NEW: Claiming boundaries
    // ------------------------------------------------------------------

    function test_claim_atExactUnlockTimestamp() public {
        vault.allocateLockedTokens(alice, 100 ether, 1);
        uint256 tge = block.timestamp + 1;
        vault.setTGETimestamp(tge);
        vm.warp(tge + 365 days); // exactly at boundary (>=)

        vm.prank(alice);
        vault.claim();
        assertEq(tenx.balanceOf(alice), 100 ether);
    }

    function test_claim_oneSecondBeforeUnlock_reverts() public {
        vault.allocateLockedTokens(alice, 100 ether, 1);
        uint256 tge = block.timestamp + 1;
        vault.setTGETimestamp(tge);
        vm.warp(tge + 365 days - 1);

        vm.prank(alice);
        vm.expectRevert("MarketingVault: not unlocked yet");
        vault.claim();
    }

    function test_claim_multipleUsersSequential_globalLockedCorrect() public {
        vault.allocateLockedTokens(alice, 100 ether, 1);
        vault.allocateLockedTokens(bob, 200 ether, 1);

        uint256 tge = block.timestamp + 1;
        vault.setTGETimestamp(tge);
        vm.warp(tge + 365 days);

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
        uint256 tge = block.timestamp + 1;
        vault.setTGETimestamp(tge);
        vm.warp(tge + 365 days);

        vm.prank(alice);
        vault.claim();

        vm.prank(alice);
        vm.expectRevert("MarketingVault: nothing to claim");
        vault.claim();
    }

    function test_claim_multiSeason_eventAmount() public {
        vault.allocateLockedTokens(alice, 100 ether, 1);
        vault.allocateLockedTokens(alice, 200 ether, 2);

        uint256 tge = block.timestamp + 1;
        vault.setTGETimestamp(tge);
        vm.warp(tge + 365 days);

        vm.expectEmit(true, false, false, true);
        emit Claimed(alice, 300 ether);

        vm.prank(alice);
        vault.claim();
    }

    // ------------------------------------------------------------------
    // NEW: Access control
    // ------------------------------------------------------------------

    function test_claimFor_distributorCannotClaimFor() public {
        vault.allocateLockedTokens(alice, 100 ether, 1);
        vault.setDistributor(distributor, true);

        uint256 tge = block.timestamp + 1;
        vault.setTGETimestamp(tge);
        vm.warp(tge + 365 days);

        vm.prank(distributor);
        vm.expectRevert();
        vault.claimFor(alice);
    }

    function test_claimFor_zeroAddress_reverts() public {
        uint256 tge = block.timestamp + 1;
        vault.setTGETimestamp(tge);
        vm.warp(tge + 365 days);

        vm.expectRevert("MarketingVault: nothing to claim");
        vault.claimFor(address(0));
    }

    // ------------------------------------------------------------------
    // NEW: Deposits
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
    // NEW: Lock & TGE
    // ------------------------------------------------------------------

    function test_setLockEnforced_true_emitsEvent() public {
        vault.setLockEnforced(false);

        vm.expectEmit(false, false, false, true);
        emit LockEnforcedUpdated(true);

        vault.setLockEnforced(true);
    }

    function test_setTGE_revert_currentTimestamp() public {
        vm.expectRevert("MarketingVault: TGE must be in future");
        vault.setTGETimestamp(block.timestamp);
    }

    // ------------------------------------------------------------------
    // NEW: View defaults
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

        uint256 tge = block.timestamp + 1;
        vault.setTGETimestamp(tge);
        vm.warp(tge + 365 days);

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
    // NEW: Rescue extras
    // ------------------------------------------------------------------

    function test_rescueTokens_revert_nonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.rescueTokens(address(tenx), alice, 100 ether);
    }

    function test_rescueTokens_exactSurplus() public {
        vault.allocateLockedTokens(alice, 100 ether, 1);

        // Vault has 1M, 100 locked → surplus = 999_900
        vault.rescueTokens(address(tenx), owner, 999_900 ether);
        assertEq(tenx.balanceOf(address(vault)), 100 ether);
    }

    function test_rescueTokens_tenxAfterClaim() public {
        vault.allocateLockedTokens(alice, 100 ether, 1);

        uint256 tge = block.timestamp + 1;
        vault.setTGETimestamp(tge);
        vm.warp(tge + 365 days);

        vm.prank(alice);
        vault.claim();

        // After claim, globalLocked drops by 100 → all vault balance is rescuable
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
