// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/Prime10XBadgeSBT.sol";

contract Prime10XBadgeSBTTest is Test {
    Prime10XBadgeSBT public badge;
    address public owner;
    address public alice;
    address public bob;

    event BadgeMinted(address indexed to, uint256 indexed tokenId, uint256 season, uint256 badgeType);
    event BadgeRevoked(address indexed from, uint256 indexed tokenId);

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        badge = new Prime10XBadgeSBT();
    }

    // ------------------------------------------------------------------
    // Deploy
    // ------------------------------------------------------------------

    function test_constructor() public view {
        assertEq(badge.name(), "Prime10X Badge");
        assertEq(badge.symbol(), "P10X-SBT");
        assertEq(badge.owner(), owner);
        assertEq(badge.totalSupply(), 0);
    }

    // ------------------------------------------------------------------
    // Minting
    // ------------------------------------------------------------------

    function test_mintBadge_success() public {
        vm.expectEmit(true, true, false, true);
        emit BadgeMinted(alice, 1, 1, 0);

        badge.mintBadge(alice, 1, 0);

        assertEq(badge.ownerOf(1), alice);
        assertEq(badge.totalSupply(), 1);
        assertEq(badge.walletOf(alice, 1), 1);
    }

    function test_mintBadge_sequentialIds() public {
        badge.mintBadge(alice, 1, 0);
        badge.mintBadge(bob, 1, 1);
        badge.mintBadge(alice, 2, 2);

        assertEq(badge.ownerOf(1), alice);
        assertEq(badge.ownerOf(2), bob);
        assertEq(badge.ownerOf(3), alice);
        assertEq(badge.totalSupply(), 3);
    }

    function test_mintBadge_allBadgeTypes() public {
        for (uint256 i = 0; i <= 5; i++) {
            address recipient = makeAddr(string(abi.encodePacked("user", i)));
            badge.mintBadge(recipient, 1, i);
        }
        assertEq(badge.totalSupply(), 6);
    }

    function test_mintBadge_revert_nonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        badge.mintBadge(alice, 1, 0);
    }

    function test_mintBadge_revert_zeroSeason() public {
        vm.expectRevert(Prime10XBadgeSBT.InvalidSeason.selector);
        badge.mintBadge(alice, 0, 0);
    }

    function test_mintBadge_revert_invalidBadgeType() public {
        vm.expectRevert(Prime10XBadgeSBT.InvalidBadgeType.selector);
        badge.mintBadge(alice, 1, 6);
    }

    function test_mintBadge_revert_duplicate() public {
        badge.mintBadge(alice, 1, 0);

        vm.expectRevert(Prime10XBadgeSBT.BadgeAlreadyAssigned.selector);
        badge.mintBadge(alice, 1, 1);
    }

    // ------------------------------------------------------------------
    // Revoke
    // ------------------------------------------------------------------

    function test_revokeBadge_success() public {
        badge.mintBadge(alice, 1, 0);

        vm.expectEmit(true, true, false, false);
        emit BadgeRevoked(alice, 1);

        badge.revokeBadge(1);

        assertEq(badge.totalSupply(), 0);
        assertEq(badge.walletOf(alice, 1), 0);
    }

    function test_revokeBadge_clearsMapping_allowsRemint() public {
        badge.mintBadge(alice, 1, 0);
        badge.revokeBadge(1);

        // Should allow re-minting for the same season
        badge.mintBadge(alice, 1, 2);
        assertEq(badge.ownerOf(2), alice);
        assertEq(badge.walletOf(alice, 1), 2);
    }

    function test_revokeBadge_revert_nonOwner() public {
        badge.mintBadge(alice, 1, 0);

        vm.prank(alice);
        vm.expectRevert();
        badge.revokeBadge(1);
    }

    function test_revokeBadge_revert_nonexistent() public {
        vm.expectRevert();
        badge.revokeBadge(999);
    }

    // ------------------------------------------------------------------
    // Soulbound enforcement
    // ------------------------------------------------------------------

    function test_transferFrom_reverts() public {
        badge.mintBadge(alice, 1, 0);

        vm.expectRevert(Prime10XBadgeSBT.Soulbound.selector);
        badge.transferFrom(alice, bob, 1);
    }

    function test_safeTransferFrom_reverts() public {
        badge.mintBadge(alice, 1, 0);

        vm.expectRevert(Prime10XBadgeSBT.Soulbound.selector);
        badge.safeTransferFrom(alice, bob, 1, "");
    }

    function test_approve_reverts() public {
        vm.expectRevert(Prime10XBadgeSBT.Soulbound.selector);
        badge.approve(bob, 1);
    }

    function test_setApprovalForAll_reverts() public {
        vm.expectRevert(Prime10XBadgeSBT.Soulbound.selector);
        badge.setApprovalForAll(bob, true);
    }

    // ------------------------------------------------------------------
    // Metadata
    // ------------------------------------------------------------------

    function test_tokenURI_format() public {
        badge.mintBadge(alice, 3, 2);

        string memory uri = badge.tokenURI(1);
        assertEq(uri, "https://prime10x.com/badges/season/3/2.json");
    }

    function test_tokenURI_revert_nonexistent() public {
        vm.expectRevert();
        badge.tokenURI(999);
    }

    // ------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------

    function test_walletOf_returnsZeroForNone() public view {
        assertEq(badge.walletOf(alice, 1), 0);
    }

    function test_totalSupply_tracksCorrectly() public {
        badge.mintBadge(alice, 1, 0);
        badge.mintBadge(bob, 1, 1);
        assertEq(badge.totalSupply(), 2);

        badge.revokeBadge(1);
        assertEq(badge.totalSupply(), 1);
    }

    // ------------------------------------------------------------------
    // NEW: Minting edge cases
    // ------------------------------------------------------------------

    function test_mintBadge_revert_zeroAddress() public {
        vm.expectRevert();
        badge.mintBadge(address(0), 1, 0);
    }

    function test_mintBadge_badgeType5_succeeds() public {
        badge.mintBadge(alice, 1, 5);
        assertEq(badge.ownerOf(1), alice);
    }

    function test_mintBadge_badgeType255_reverts() public {
        vm.expectRevert(Prime10XBadgeSBT.InvalidBadgeType.selector);
        badge.mintBadge(alice, 1, 255);
    }

    function test_mintBadge_badgeType6_reverts() public {
        vm.expectRevert(Prime10XBadgeSBT.InvalidBadgeType.selector);
        badge.mintBadge(alice, 1, 6);
    }

    function test_mintBadge_multipleUsersSameSeasonDifferentTypes() public {
        badge.mintBadge(alice, 1, 0);
        badge.mintBadge(bob, 1, 3);

        assertEq(badge.walletOf(alice, 1), 1);
        assertEq(badge.walletOf(bob, 1), 2);
        assertEq(badge.totalSupply(), 2);
    }

    function test_mintBadge_sameUserDifferentSeasons() public {
        badge.mintBadge(alice, 1, 0);
        badge.mintBadge(alice, 2, 1);
        badge.mintBadge(alice, 3, 2);

        assertEq(badge.walletOf(alice, 1), 1);
        assertEq(badge.walletOf(alice, 2), 2);
        assertEq(badge.walletOf(alice, 3), 3);
        assertEq(badge.totalSupply(), 3);
    }

    // ------------------------------------------------------------------
    // NEW: Revoke state verification
    // ------------------------------------------------------------------

    function test_revokeBadge_remintDifferentType() public {
        badge.mintBadge(alice, 1, 0);
        badge.revokeBadge(1);

        badge.mintBadge(alice, 1, 4);
        assertEq(badge.ownerOf(2), alice);
        assertEq(badge.walletOf(alice, 1), 2);
    }

    function test_revokeBadge_ownerOf_reverts() public {
        badge.mintBadge(alice, 1, 0);
        badge.revokeBadge(1);

        vm.expectRevert();
        badge.ownerOf(1);
    }

    function test_revokeBadge_tokenURI_reverts() public {
        badge.mintBadge(alice, 1, 0);
        badge.revokeBadge(1);

        vm.expectRevert();
        badge.tokenURI(1);
    }

    // ------------------------------------------------------------------
    // NEW: Views & metadata
    // ------------------------------------------------------------------

    function test_walletOf_nonexistentSeason() public view {
        assertEq(badge.walletOf(alice, 999), 0);
    }

    function test_walletOf_zeroAddress() public view {
        assertEq(badge.walletOf(address(0), 1), 0);
    }

    function test_balanceOf_correctCount() public {
        badge.mintBadge(alice, 1, 0);
        badge.mintBadge(alice, 2, 1);
        badge.mintBadge(alice, 3, 2);

        assertEq(badge.balanceOf(alice), 3);

        badge.revokeBadge(2);
        assertEq(badge.balanceOf(alice), 2);
    }

    function test_tokenURI_season1_type0() public {
        badge.mintBadge(alice, 1, 0);
        assertEq(badge.tokenURI(1), "https://prime10x.com/badges/season/1/0.json");
    }

    // ------------------------------------------------------------------
    // NEW: Soulbound extras
    // ------------------------------------------------------------------

    function test_getApproved_returnsZero() public {
        badge.mintBadge(alice, 1, 0);
        assertEq(badge.getApproved(1), address(0));
    }

    function test_isApprovedForAll_returnsFalse() public view {
        assertFalse(badge.isApprovedForAll(alice, bob));
    }

    function test_safeTransferFrom_3arg_reverts() public {
        badge.mintBadge(alice, 1, 0);

        vm.expectRevert(Prime10XBadgeSBT.Soulbound.selector);
        badge.safeTransferFrom(alice, bob, 1);
    }
}
