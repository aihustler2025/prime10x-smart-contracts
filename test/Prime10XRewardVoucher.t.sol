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
    event EmergencyAdminUpdated(address admin);
    event VoucherRaffleConfigured(uint256 indexed raffleId, uint256 seasonId, bytes32 merkleRoot, bool active);
    event VoucherClaimed(address indexed claimer, uint256 indexed raffleId, uint256 indexed tokenId, uint256 tenxAmount, uint256 seasonId);

    address public emergencyAdmin;

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        emergencyAdmin = makeAddr("emergencyAdmin");

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

    // ------------------------------------------------------------------
    // Emergency Admin
    // ------------------------------------------------------------------

    function test_setEmergencyAdmin_success() public {
        vm.expectEmit(false, false, false, true);
        emit EmergencyAdminUpdated(emergencyAdmin);

        voucher.setEmergencyAdmin(emergencyAdmin);
    }

    function test_setEmergencyAdmin_revert_nonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        voucher.setEmergencyAdmin(emergencyAdmin);
    }

    function test_emergencyUpdateClaimDate_success() public {
        voucher.setEmergencyAdmin(emergencyAdmin);

        uint256 newDate = block.timestamp + 90 days;

        vm.expectEmit(false, false, false, true);
        emit ClaimEnableDateSet(newDate);

        vm.prank(emergencyAdmin);
        voucher.emergencyUpdateClaimDate(newDate);

        assertEq(voucher.claimEnableDate(), newDate);
        assertTrue(voucher.claimEnableDateSet());
    }

    function test_emergencyUpdateClaimDate_revert_nonAdmin() public {
        voucher.setEmergencyAdmin(emergencyAdmin);

        vm.prank(alice);
        vm.expectRevert("RewardVoucher: not emergency admin");
        voucher.emergencyUpdateClaimDate(block.timestamp + 90 days);
    }

    function test_emergencyUpdateClaimDate_revert_zeroDate() public {
        voucher.setEmergencyAdmin(emergencyAdmin);

        vm.prank(emergencyAdmin);
        vm.expectRevert("RewardVoucher: invalid date");
        voucher.emergencyUpdateClaimDate(0);
    }

    // ------------------------------------------------------------------
    // Merkle-claim helpers
    // ------------------------------------------------------------------

    function _leaf(address claimer, uint256 raffleId, uint256 tenxAmount) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(claimer, raffleId, tenxAmount))));
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    // ------------------------------------------------------------------
    // setVoucherRaffle
    // ------------------------------------------------------------------

    function test_setVoucherRaffle_onlyOwner() public {
        bytes32 root = _leaf(alice, 1, 100 ether);
        vm.prank(alice);
        vm.expectRevert();
        voucher.setVoucherRaffle(1, 1, root, true);
    }

    function test_setVoucherRaffle_revert_zeroSeason() public {
        bytes32 root = _leaf(alice, 1, 100 ether);
        vm.expectRevert("RewardVoucher: invalid season");
        voucher.setVoucherRaffle(1, 0, root, true);
    }

    function test_setVoucherRaffle_revert_zeroRoot() public {
        vm.expectRevert("RewardVoucher: invalid root");
        voucher.setVoucherRaffle(1, 1, bytes32(0), true);
    }

    function test_setVoucherRaffle_overwrites() public {
        bytes32 root1 = _leaf(alice, 1, 100 ether);
        bytes32 root2 = _leaf(bob, 1, 200 ether);

        voucher.setVoucherRaffle(1, 1, root1, true);
        voucher.setVoucherRaffle(1, 2, root2, false);

        (uint256 seasonId, bytes32 merkleRoot, bool active) = voucher.getVoucherRaffle(1);
        assertEq(seasonId, 2);
        assertEq(merkleRoot, root2);
        assertEq(active, false);
    }

    function test_setVoucherRaffle_emitsEvent() public {
        bytes32 root = _leaf(alice, 1, 100 ether);
        vm.expectEmit(true, false, false, true);
        emit VoucherRaffleConfigured(1, 1, root, true);
        voucher.setVoucherRaffle(1, 1, root, true);
    }

    // ------------------------------------------------------------------
    // setVoucherRaffleActive
    // ------------------------------------------------------------------

    function test_setVoucherRaffleActive_toggles() public {
        bytes32 root = _leaf(alice, 1, 100 ether);
        voucher.setVoucherRaffle(1, 1, root, true);

        voucher.setVoucherRaffleActive(1, false);
        ( , , bool active) = voucher.getVoucherRaffle(1);
        assertEq(active, false);

        voucher.setVoucherRaffleActive(1, true);
        ( , , active) = voucher.getVoucherRaffle(1);
        assertEq(active, true);
    }

    function test_setVoucherRaffleActive_revert_notConfigured() public {
        vm.expectRevert("RewardVoucher: raffle not configured");
        voucher.setVoucherRaffleActive(99, true);
    }

    // ------------------------------------------------------------------
    // claimVoucher — single-leaf tree (proof = empty array)
    // ------------------------------------------------------------------

    function test_claimVoucher_singleWinner() public {
        uint256 raffleId = 1;
        uint256 tenxAmount = 500 ether;
        bytes32 leaf = _leaf(alice, raffleId, tenxAmount);
        // Single-leaf tree: leaf is the root.
        voucher.setVoucherRaffle(raffleId, 7, leaf, true);

        bytes32[] memory proof = new bytes32[](0);

        vm.prank(alice);
        voucher.claimVoucher(raffleId, tenxAmount, proof);

        // Token minted to alice (tokenId 1, since fresh contract).
        assertEq(voucher.ownerOf(1), alice);
        assertEq(voucher.totalSupply(), 1);
        (uint256 amt, uint256 season, bool redeemed) = voucher.getVoucherInfo(1);
        assertEq(amt, tenxAmount);
        assertEq(season, 7);
        assertEq(redeemed, false);
        assertTrue(voucher.hasClaimed(raffleId, alice));
    }

    function test_claimVoucher_emitsEvents() public {
        uint256 raffleId = 1;
        uint256 tenxAmount = 500 ether;
        bytes32 leaf = _leaf(alice, raffleId, tenxAmount);
        voucher.setVoucherRaffle(raffleId, 7, leaf, true);

        bytes32[] memory proof = new bytes32[](0);

        vm.expectEmit(true, true, true, true);
        emit VoucherClaimed(alice, raffleId, 1, tenxAmount, 7);
        vm.expectEmit(true, true, false, true);
        emit VoucherMinted(alice, 1, tenxAmount, 7);

        vm.prank(alice);
        voucher.claimVoucher(raffleId, tenxAmount, proof);
    }

    function test_claimVoucher_revert_invalidProof() public {
        uint256 raffleId = 1;
        bytes32 leaf = _leaf(alice, raffleId, 500 ether);
        voucher.setVoucherRaffle(raffleId, 7, leaf, true);

        // Bob submits a proof for himself, but the root is alice's leaf.
        bytes32[] memory proof = new bytes32[](0);
        vm.prank(bob);
        vm.expectRevert("RewardVoucher: invalid proof");
        voucher.claimVoucher(raffleId, 500 ether, proof);
    }

    function test_claimVoucher_revert_wrongAmount() public {
        uint256 raffleId = 1;
        bytes32 leaf = _leaf(alice, raffleId, 500 ether);
        voucher.setVoucherRaffle(raffleId, 7, leaf, true);

        // Same address, same raffleId — but wrong amount.
        bytes32[] memory proof = new bytes32[](0);
        vm.prank(alice);
        vm.expectRevert("RewardVoucher: invalid proof");
        voucher.claimVoucher(raffleId, 999 ether, proof);
    }

    function test_claimVoucher_revert_alreadyClaimed() public {
        uint256 raffleId = 1;
        uint256 tenxAmount = 500 ether;
        bytes32 leaf = _leaf(alice, raffleId, tenxAmount);
        voucher.setVoucherRaffle(raffleId, 7, leaf, true);

        bytes32[] memory proof = new bytes32[](0);

        vm.prank(alice);
        voucher.claimVoucher(raffleId, tenxAmount, proof);

        vm.prank(alice);
        vm.expectRevert("RewardVoucher: already claimed");
        voucher.claimVoucher(raffleId, tenxAmount, proof);
    }

    function test_claimVoucher_revert_inactive() public {
        uint256 raffleId = 1;
        bytes32 leaf = _leaf(alice, raffleId, 500 ether);
        voucher.setVoucherRaffle(raffleId, 7, leaf, false);

        bytes32[] memory proof = new bytes32[](0);
        vm.prank(alice);
        vm.expectRevert("RewardVoucher: raffle inactive");
        voucher.claimVoucher(raffleId, 500 ether, proof);
    }

    function test_claimVoucher_revert_notConfigured() public {
        bytes32[] memory proof = new bytes32[](0);
        vm.prank(alice);
        vm.expectRevert("RewardVoucher: raffle not configured");
        voucher.claimVoucher(99, 500 ether, proof);
    }

    function test_claimVoucher_revert_zeroAmount() public {
        uint256 raffleId = 1;
        bytes32 leaf = _leaf(alice, raffleId, 1 ether);
        voucher.setVoucherRaffle(raffleId, 7, leaf, true);

        bytes32[] memory proof = new bytes32[](0);
        vm.prank(alice);
        vm.expectRevert("RewardVoucher: invalid amount");
        voucher.claimVoucher(raffleId, 0, proof);
    }

    // ------------------------------------------------------------------
    // claimVoucher — multi-leaf tree (real proof)
    // ------------------------------------------------------------------

    function test_claimVoucher_multipleWinners() public {
        uint256 raffleId = 42;
        uint256 amountA = 100 ether;
        uint256 amountB = 200 ether;

        bytes32 leafA = _leaf(alice, raffleId, amountA);
        bytes32 leafB = _leaf(bob, raffleId, amountB);
        bytes32 root = _hashPair(leafA, leafB);

        voucher.setVoucherRaffle(raffleId, 3, root, true);

        // alice claims with proof = [leafB]
        bytes32[] memory proofA = new bytes32[](1);
        proofA[0] = leafB;
        vm.prank(alice);
        voucher.claimVoucher(raffleId, amountA, proofA);

        // bob claims with proof = [leafA]
        bytes32[] memory proofB = new bytes32[](1);
        proofB[0] = leafA;
        vm.prank(bob);
        voucher.claimVoucher(raffleId, amountB, proofB);

        assertEq(voucher.totalSupply(), 2);
        assertEq(voucher.ownerOf(1), alice);
        assertEq(voucher.ownerOf(2), bob);
        assertTrue(voucher.hasClaimed(raffleId, alice));
        assertTrue(voucher.hasClaimed(raffleId, bob));
    }

    // ------------------------------------------------------------------
    // Soulbound enforcement on claimed tokens
    // ------------------------------------------------------------------

    function test_claimedVoucher_isSoulbound() public {
        uint256 raffleId = 1;
        uint256 tenxAmount = 500 ether;
        bytes32 leaf = _leaf(alice, raffleId, tenxAmount);
        voucher.setVoucherRaffle(raffleId, 7, leaf, true);

        bytes32[] memory proof = new bytes32[](0);
        vm.prank(alice);
        voucher.claimVoucher(raffleId, tenxAmount, proof);

        vm.prank(alice);
        vm.expectRevert("Voucher is soulbound");
        voucher.transferFrom(alice, bob, 1);
    }

    // ------------------------------------------------------------------
    // hasClaimed view
    // ------------------------------------------------------------------

    function test_hasClaimed_returnsCorrectState() public {
        uint256 raffleId = 1;
        bytes32 leaf = _leaf(alice, raffleId, 500 ether);
        voucher.setVoucherRaffle(raffleId, 7, leaf, true);

        assertFalse(voucher.hasClaimed(raffleId, alice));

        bytes32[] memory proof = new bytes32[](0);
        vm.prank(alice);
        voucher.claimVoucher(raffleId, 500 ether, proof);

        assertTrue(voucher.hasClaimed(raffleId, alice));
        assertFalse(voucher.hasClaimed(raffleId, bob));
        assertFalse(voucher.hasClaimed(99, alice));
    }
}
