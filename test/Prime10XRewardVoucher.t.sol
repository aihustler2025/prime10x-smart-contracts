// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/Prime10XRewardVoucher.sol";

contract Prime10XRewardVoucherTest is Test {
    Prime10XRewardVoucher public voucher;
    address public owner;
    address public alice;
    address public bob;

    event VoucherMinted(address indexed to, uint256 indexed tokenId, uint256 tenxAmount, uint256 seasonId);
    event VoucherRedeemed(address indexed redeemer, uint256 indexed tokenId, uint256 tenxAmount, uint256 seasonId);
    event VoucherRevoked(address indexed from, uint256 indexed tokenId);
    event BaseURIUpdated(string newBaseURI);
    event ClaimEnableDateSet(uint256 claimEnableDate);

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        voucher = new Prime10XRewardVoucher("Prime10X Voucher", "P10X-V");
    }

    // ------------------------------------------------------------------
    // Deploy
    // ------------------------------------------------------------------

    function test_constructor() public view {
        assertEq(voucher.name(), "Prime10X Voucher");
        assertEq(voucher.symbol(), "P10X-V");
        assertEq(voucher.owner(), owner);
        assertEq(voucher.totalSupply(), 0);
    }

    // ------------------------------------------------------------------
    // Minting
    // ------------------------------------------------------------------

    function test_mintVoucher_success() public {
        vm.expectEmit(true, true, false, true);
        emit VoucherMinted(alice, 1, 500 ether, 1);

        voucher.mintVoucher(alice, 500 ether, 1);

        assertEq(voucher.ownerOf(1), alice);
        assertEq(voucher.totalSupply(), 1);

        (uint256 amount, uint256 seasonId, bool redeemed) = voucher.getVoucherInfo(1);
        assertEq(amount, 500 ether);
        assertEq(seasonId, 1);
        assertFalse(redeemed);
    }

    function test_mintVoucher_sequentialIds() public {
        voucher.mintVoucher(alice, 100 ether, 1);
        voucher.mintVoucher(bob, 200 ether, 1);
        voucher.mintVoucher(alice, 300 ether, 2);

        assertEq(voucher.ownerOf(1), alice);
        assertEq(voucher.ownerOf(2), bob);
        assertEq(voucher.ownerOf(3), alice);
        assertEq(voucher.totalSupply(), 3);
    }

    function test_mintVoucher_revert_nonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        voucher.mintVoucher(alice, 100 ether, 1);
    }

    function test_mintVoucher_revert_zeroAddress() public {
        vm.expectRevert("Invalid recipient");
        voucher.mintVoucher(address(0), 100 ether, 1);
    }

    function test_mintVoucher_revert_zeroAmount() public {
        vm.expectRevert("Invalid amount");
        voucher.mintVoucher(alice, 0, 1);
    }

    function test_mintVoucher_revert_zeroSeason() public {
        vm.expectRevert("Invalid season");
        voucher.mintVoucher(alice, 100 ether, 0);
    }

    // ------------------------------------------------------------------
    // Redeem
    // ------------------------------------------------------------------

    function test_redeemVoucher_success() public {
        voucher.mintVoucher(alice, 500 ether, 1);

        // Enable claims
        uint256 claimDate = block.timestamp + 1;
        voucher.setClaimEnableDate(claimDate);
        vm.warp(claimDate);

        vm.expectEmit(true, true, false, true);
        emit VoucherRedeemed(alice, 1, 500 ether, 1);

        vm.prank(alice);
        voucher.redeemVoucher(1);

        assertEq(voucher.totalSupply(), 0);
    }

    function test_redeemVoucher_revert_claimsNotEnabled() public {
        voucher.mintVoucher(alice, 500 ether, 1);

        vm.prank(alice);
        vm.expectRevert("RewardVoucher: claims not enabled");
        voucher.redeemVoucher(1);
    }

    function test_redeemVoucher_revert_claimDateNotPassed() public {
        voucher.mintVoucher(alice, 500 ether, 1);
        voucher.setClaimEnableDate(block.timestamp + 1 days);

        vm.prank(alice);
        vm.expectRevert("RewardVoucher: claims not enabled");
        voucher.redeemVoucher(1);
    }

    function test_redeemVoucher_revert_nonHolder() public {
        voucher.mintVoucher(alice, 500 ether, 1);

        // Enable claims
        uint256 claimDate = block.timestamp + 1;
        voucher.setClaimEnableDate(claimDate);
        vm.warp(claimDate);

        vm.prank(bob);
        vm.expectRevert("Not voucher owner");
        voucher.redeemVoucher(1);
    }

    function test_redeemVoucher_revert_nonexistent() public {
        vm.prank(alice);
        vm.expectRevert("Nonexistent token");
        voucher.redeemVoucher(999);
    }

    // ------------------------------------------------------------------
    // Revoke
    // ------------------------------------------------------------------

    function test_revokeVoucher_success() public {
        voucher.mintVoucher(alice, 500 ether, 1);

        vm.expectEmit(true, true, false, false);
        emit VoucherRevoked(alice, 1);

        voucher.revokeVoucher(1);

        assertEq(voucher.totalSupply(), 0);
    }

    function test_revokeVoucher_revert_nonOwner() public {
        voucher.mintVoucher(alice, 500 ether, 1);

        vm.prank(alice);
        vm.expectRevert();
        voucher.revokeVoucher(1);
    }

    function test_revokeVoucher_revert_alreadyRedeemed() public {
        voucher.mintVoucher(alice, 500 ether, 1);

        // Enable claims and redeem
        uint256 claimDate = block.timestamp + 1;
        voucher.setClaimEnableDate(claimDate);
        vm.warp(claimDate);

        vm.prank(alice);
        voucher.redeemVoucher(1);

        vm.expectRevert("Nonexistent token");
        voucher.revokeVoucher(1);
    }

    function test_revokeVoucher_revert_nonexistent() public {
        vm.expectRevert("Nonexistent token");
        voucher.revokeVoucher(999);
    }

    // ------------------------------------------------------------------
    // Claim enable date
    // ------------------------------------------------------------------

    function test_setClaimEnableDate() public {
        uint256 claimDate = block.timestamp + 30 days;

        vm.expectEmit(false, false, false, true);
        emit ClaimEnableDateSet(claimDate);

        voucher.setClaimEnableDate(claimDate);

        assertEq(voucher.claimEnableDate(), claimDate);
        assertTrue(voucher.claimEnableDateSet());
    }

    function test_setClaimEnableDate_canUpdate() public {
        voucher.setClaimEnableDate(block.timestamp + 30 days);

        uint256 newDate = block.timestamp + 60 days;
        voucher.setClaimEnableDate(newDate);

        assertEq(voucher.claimEnableDate(), newDate);
    }

    function test_setClaimEnableDate_revert_zeroDate() public {
        vm.expectRevert("RewardVoucher: invalid date");
        voucher.setClaimEnableDate(0);
    }

    function test_setClaimEnableDate_revert_nonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        voucher.setClaimEnableDate(block.timestamp + 30 days);
    }

    function test_isRedeemable_defaultFalse() public view {
        assertFalse(voucher.isRedeemable());
    }

    function test_isRedeemable_trueAfterDate() public {
        uint256 claimDate = block.timestamp + 1 days;
        voucher.setClaimEnableDate(claimDate);
        assertFalse(voucher.isRedeemable());

        vm.warp(claimDate);
        assertTrue(voucher.isRedeemable());
    }

    // ------------------------------------------------------------------
    // Soulbound enforcement
    // ------------------------------------------------------------------

    function test_transferFrom_reverts() public {
        voucher.mintVoucher(alice, 500 ether, 1);

        vm.expectRevert("Voucher is soulbound");
        voucher.transferFrom(alice, bob, 1);
    }

    function test_safeTransferFrom_reverts() public {
        voucher.mintVoucher(alice, 500 ether, 1);

        vm.expectRevert("Voucher is soulbound");
        voucher.safeTransferFrom(alice, bob, 1, "");
    }

    function test_approve_reverts() public {
        vm.expectRevert("Voucher is soulbound");
        voucher.approve(bob, 1);
    }

    function test_setApprovalForAll_reverts() public {
        vm.expectRevert("Voucher is soulbound");
        voucher.setApprovalForAll(bob, true);
    }

    // ------------------------------------------------------------------
    // Metadata
    // ------------------------------------------------------------------

    function test_setBaseURI() public {
        vm.expectEmit(false, false, false, true);
        emit BaseURIUpdated("https://api.prime10x.com/vouchers");

        voucher.setBaseURI("https://api.prime10x.com/vouchers");
    }

    function test_tokenURI_withBaseURI() public {
        voucher.setBaseURI("https://api.prime10x.com/vouchers");
        voucher.mintVoucher(alice, 500 ether, 3);

        string memory uri = voucher.tokenURI(1);
        assertEq(uri, "https://api.prime10x.com/vouchers/3/1.json");
    }

    function test_tokenURI_emptyWhenNoBase() public {
        voucher.mintVoucher(alice, 500 ether, 1);

        string memory uri = voucher.tokenURI(1);
        assertEq(uri, "");
    }

    function test_tokenURI_revert_nonexistent() public {
        vm.expectRevert();
        voucher.tokenURI(999);
    }

    // ------------------------------------------------------------------
    // Enumeration
    // ------------------------------------------------------------------

    function test_vouchersOf() public {
        voucher.mintVoucher(alice, 100 ether, 1);
        voucher.mintVoucher(alice, 200 ether, 2);
        voucher.mintVoucher(bob, 300 ether, 1);

        uint256[] memory aliceVouchers = voucher.vouchersOf(alice);
        assertEq(aliceVouchers.length, 2);
        assertEq(aliceVouchers[0], 1);
        assertEq(aliceVouchers[1], 2);

        uint256[] memory bobVouchers = voucher.vouchersOf(bob);
        assertEq(bobVouchers.length, 1);
        assertEq(bobVouchers[0], 3);
    }

    function test_totalSupply_tracksMintBurn() public {
        voucher.mintVoucher(alice, 100 ether, 1);
        voucher.mintVoucher(bob, 200 ether, 1);
        assertEq(voucher.totalSupply(), 2);

        // Enable claims for redeem
        uint256 claimDate = block.timestamp + 1;
        voucher.setClaimEnableDate(claimDate);
        vm.warp(claimDate);

        vm.prank(alice);
        voucher.redeemVoucher(1);
        assertEq(voucher.totalSupply(), 1);

        voucher.revokeVoucher(2);
        assertEq(voucher.totalSupply(), 0);
    }

    // ------------------------------------------------------------------
    // Interface support
    // ------------------------------------------------------------------

    function test_supportsInterface() public view {
        // ERC721
        assertTrue(voucher.supportsInterface(0x80ac58cd));
        // ERC721Enumerable
        assertTrue(voucher.supportsInterface(0x780e9d63));
        // ERC165
        assertTrue(voucher.supportsInterface(0x01ffc9a7));
    }

    // ------------------------------------------------------------------
    // NEW: Minting
    // ------------------------------------------------------------------

    function test_mintVoucher_multipleSameUserSameSeason() public {
        voucher.mintVoucher(alice, 100 ether, 1);
        voucher.mintVoucher(alice, 200 ether, 1);

        uint256[] memory ids = voucher.vouchersOf(alice);
        assertEq(ids.length, 2);
        assertEq(ids[0], 1);
        assertEq(ids[1], 2);
    }

    function test_mintVoucher_largeTenxAmount() public {
        uint256 largeAmount = type(uint256).max;
        voucher.mintVoucher(alice, largeAmount, 1);

        (uint256 amount,,) = voucher.getVoucherInfo(1);
        assertEq(amount, largeAmount);
    }

    // ------------------------------------------------------------------
    // NEW: Redeeming
    // ------------------------------------------------------------------

    function test_redeemVoucher_atExactClaimDate() public {
        voucher.mintVoucher(alice, 500 ether, 1);
        uint256 claimDate = block.timestamp + 1 days;
        voucher.setClaimEnableDate(claimDate);
        vm.warp(claimDate); // exactly at boundary (>=)

        vm.prank(alice);
        voucher.redeemVoucher(1);
        assertEq(voucher.totalSupply(), 0);
    }

    function test_redeemVoucher_oneSecondBefore_reverts() public {
        voucher.mintVoucher(alice, 500 ether, 1);
        uint256 claimDate = block.timestamp + 1 days;
        voucher.setClaimEnableDate(claimDate);
        vm.warp(claimDate - 1);

        vm.prank(alice);
        vm.expectRevert("RewardVoucher: claims not enabled");
        voucher.redeemVoucher(1);
    }

    function test_redeemVoucher_afterDateUpdate() public {
        voucher.mintVoucher(alice, 500 ether, 1);

        // Set date in the future
        voucher.setClaimEnableDate(block.timestamp + 1 days);

        // Update to a past date — makes immediately redeemable
        voucher.setClaimEnableDate(block.timestamp);

        vm.prank(alice);
        voucher.redeemVoucher(1);
        assertEq(voucher.totalSupply(), 0);
    }

    function test_redeemVoucher_correctEventData() public {
        voucher.mintVoucher(alice, 500 ether, 3);
        uint256 claimDate = block.timestamp + 1;
        voucher.setClaimEnableDate(claimDate);
        vm.warp(claimDate);

        vm.expectEmit(true, true, false, true);
        emit VoucherRedeemed(alice, 1, 500 ether, 3);

        vm.prank(alice);
        voucher.redeemVoucher(1);
    }

    // ------------------------------------------------------------------
    // NEW: Revoke & enumeration
    // ------------------------------------------------------------------

    function test_revokeVoucher_enumerationCorrectAfter() public {
        voucher.mintVoucher(alice, 100 ether, 1); // id 1
        voucher.mintVoucher(alice, 200 ether, 1); // id 2
        voucher.mintVoucher(alice, 300 ether, 1); // id 3

        voucher.revokeVoucher(2); // revoke middle

        uint256[] memory ids = voucher.vouchersOf(alice);
        assertEq(ids.length, 2);
        // After ERC721Enumerable swap-and-pop, order may change
        assertTrue(ids[0] == 1 || ids[0] == 3);
        assertTrue(ids[1] == 1 || ids[1] == 3);
        assertTrue(ids[0] != ids[1]);
    }

    function test_revokeVoucher_thenMintAgain_newId() public {
        voucher.mintVoucher(alice, 100 ether, 1); // id 1
        voucher.revokeVoucher(1);

        voucher.mintVoucher(alice, 200 ether, 1); // id 2 (not reused)
        assertEq(voucher.ownerOf(2), alice);
        assertEq(voucher.totalSupply(), 1);
    }

    // ------------------------------------------------------------------
    // NEW: View edge cases
    // ------------------------------------------------------------------

    function test_getVoucherInfo_afterRedeem_reverts() public {
        voucher.mintVoucher(alice, 500 ether, 1);
        uint256 claimDate = block.timestamp + 1;
        voucher.setClaimEnableDate(claimDate);
        vm.warp(claimDate);

        vm.prank(alice);
        voucher.redeemVoucher(1);

        vm.expectRevert("Nonexistent token");
        voucher.getVoucherInfo(1);
    }

    function test_getVoucherInfo_afterRevoke_reverts() public {
        voucher.mintVoucher(alice, 500 ether, 1);
        voucher.revokeVoucher(1);

        vm.expectRevert("Nonexistent token");
        voucher.getVoucherInfo(1);
    }

    function test_vouchersOf_emptyResult() public view {
        uint256[] memory ids = voucher.vouchersOf(alice);
        assertEq(ids.length, 0);
    }

    function test_vouchersOf_afterAllRedeemed() public {
        voucher.mintVoucher(alice, 100 ether, 1);
        voucher.mintVoucher(alice, 200 ether, 1);

        uint256 claimDate = block.timestamp + 1;
        voucher.setClaimEnableDate(claimDate);
        vm.warp(claimDate);

        vm.startPrank(alice);
        voucher.redeemVoucher(1);
        voucher.redeemVoucher(2);
        vm.stopPrank();

        uint256[] memory ids = voucher.vouchersOf(alice);
        assertEq(ids.length, 0);
    }

    function test_balanceOf_correctCount() public {
        voucher.mintVoucher(alice, 100 ether, 1);
        voucher.mintVoucher(alice, 200 ether, 1);
        assertEq(voucher.balanceOf(alice), 2);

        voucher.revokeVoucher(1);
        assertEq(voucher.balanceOf(alice), 1);

        uint256 claimDate = block.timestamp + 1;
        voucher.setClaimEnableDate(claimDate);
        vm.warp(claimDate);

        vm.prank(alice);
        voucher.redeemVoucher(2);
        assertEq(voucher.balanceOf(alice), 0);
    }

    // ------------------------------------------------------------------
    // NEW: Claim date
    // ------------------------------------------------------------------

    function test_setClaimEnableDate_multipleTimes_latestMatters() public {
        voucher.setClaimEnableDate(block.timestamp + 30 days);
        voucher.setClaimEnableDate(block.timestamp + 60 days);

        assertEq(voucher.claimEnableDate(), block.timestamp + 60 days);
    }

    function test_setClaimEnableDate_pastDate_succeeds() public {
        // Warp forward so we have a past timestamp to use
        vm.warp(1000);
        voucher.setClaimEnableDate(500);

        assertTrue(voucher.isRedeemable());
    }

    // ------------------------------------------------------------------
    // NEW: Metadata
    // ------------------------------------------------------------------

    function test_setBaseURI_emptyString() public {
        voucher.setBaseURI("https://api.prime10x.com/vouchers");
        voucher.mintVoucher(alice, 500 ether, 1);

        // Clear base URI
        voucher.setBaseURI("");

        string memory uri = voucher.tokenURI(1);
        assertEq(uri, "");
    }

    function test_setBaseURI_revert_nonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        voucher.setBaseURI("https://evil.com");
    }

    function test_tokenURI_differentSeasons() public {
        voucher.setBaseURI("https://api.prime10x.com/vouchers");
        voucher.mintVoucher(alice, 100 ether, 1); // id 1
        voucher.mintVoucher(alice, 200 ether, 5); // id 2

        assertEq(voucher.tokenURI(1), "https://api.prime10x.com/vouchers/1/1.json");
        assertEq(voucher.tokenURI(2), "https://api.prime10x.com/vouchers/5/2.json");
    }

    // ------------------------------------------------------------------
    // NEW: Interface
    // ------------------------------------------------------------------

    function test_supportsInterface_unsupported_returnsFalse() public view {
        assertFalse(voucher.supportsInterface(0xffffffff));
        assertFalse(voucher.supportsInterface(0xdeadbeef));
    }
}
