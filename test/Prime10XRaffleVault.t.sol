// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/Prime10XRaffleVault.sol";
import "./mocks/MockTENX.sol";

contract Prime10XRaffleVaultTest is Test {
    Prime10XRaffleVault public vault;
    MockTENX public tenx;
    address public owner;
    address public alice;
    address public bob;
    address public carol;
    address public dave;

    // Merkle tree data (4 leaves)
    bytes32 public merkleRoot;
    bytes32[] public proofAlice;
    bytes32[] public proofBob;

    uint256 constant RAFFLE_ID = 1;
    uint256 constant SEASON_ID = 1;
    uint8 constant TIER = 0;
    uint256 constant POOL = 1000 ether;
    uint256 constant ALICE_AMOUNT = 100 ether;
    uint256 constant BOB_AMOUNT = 200 ether;

    event RaffleConfigured(
        uint256 indexed raffleId, uint256 seasonId, uint8 tier, bytes32 merkleRoot, uint256 totalTenxPool, bool active
    );
    event RaffleClaimed(address indexed user, uint256 indexed raffleId, uint256 amount);
    event TGETimestampSet(uint256 tgeTimestamp);
    event LockEnforcedUpdated(bool enforced);
    event TokensRescued(address indexed token, address indexed to, uint256 amount);

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");
        dave = makeAddr("dave");

        tenx = new MockTENX();
        vault = new Prime10XRaffleVault(address(tenx), owner);

        // Fund vault
        tenx.mint(address(vault), 10_000 ether);

        // Build a 4-leaf Merkle tree:
        // leaf0 = hash(alice, RAFFLE_ID, 100e18)
        // leaf1 = hash(bob, RAFFLE_ID, 200e18)
        // leaf2 = hash(carol, RAFFLE_ID, 150e18)
        // leaf3 = hash(dave, RAFFLE_ID, 50e18)
        bytes32 leaf0 = _makeLeaf(alice, RAFFLE_ID, ALICE_AMOUNT);
        bytes32 leaf1 = _makeLeaf(bob, RAFFLE_ID, BOB_AMOUNT);
        bytes32 leaf2 = _makeLeaf(carol, RAFFLE_ID, uint256(150 ether));
        bytes32 leaf3 = _makeLeaf(dave, RAFFLE_ID, uint256(50 ether));

        // Level 1
        bytes32 hash01 = _hashPair(leaf0, leaf1);
        bytes32 hash23 = _hashPair(leaf2, leaf3);

        // Root
        merkleRoot = _hashPair(hash01, hash23);

        // Proof for alice (leaf0): [leaf1, hash23]
        proofAlice = new bytes32[](2);
        proofAlice[0] = leaf1;
        proofAlice[1] = hash23;

        // Proof for bob (leaf1): [leaf0, hash23]
        proofBob = new bytes32[](2);
        proofBob[0] = leaf0;
        proofBob[1] = hash23;
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function _makeLeaf(address user, uint256 raffleId, uint256 amount) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(user, raffleId, amount))));
    }

    function _createDefaultRaffle() internal {
        vault.createOrUpdateRaffle(RAFFLE_ID, SEASON_ID, TIER, merkleRoot, POOL, true);
    }

    function _unlockVault() internal {
        vault.setLockEnforced(false);
    }

    // ------------------------------------------------------------------
    // Deploy
    // ------------------------------------------------------------------

    function test_constructor() public view {
        assertEq(address(vault.tenxToken()), address(tenx));
        assertEq(vault.owner(), owner);
    }

    function test_constructor_revert_zeroToken() public {
        vm.expectRevert("RaffleVault: zero token");
        new Prime10XRaffleVault(address(0), owner);
    }

    // ------------------------------------------------------------------
    // Raffle management
    // ------------------------------------------------------------------

    function test_createRaffle() public {
        vm.expectEmit(true, false, false, true);
        emit RaffleConfigured(RAFFLE_ID, SEASON_ID, TIER, merkleRoot, POOL, true);

        _createDefaultRaffle();

        (uint256 sId, uint8 t, bytes32 mr, uint256 pool, uint256 claimed, bool active) = vault.getRaffle(RAFFLE_ID);
        assertEq(sId, SEASON_ID);
        assertEq(t, TIER);
        assertEq(mr, merkleRoot);
        assertEq(pool, POOL);
        assertEq(claimed, 0);
        assertTrue(active);
        assertEq(vault.totalPoolAllocated(), POOL);
    }

    function test_updateRaffle() public {
        _createDefaultRaffle();
        bytes32 newRoot = keccak256("new");

        vault.createOrUpdateRaffle(RAFFLE_ID, 2, 1, newRoot, 2000 ether, false);

        (uint256 sId, uint8 t, bytes32 mr, uint256 pool,, bool active) = vault.getRaffle(RAFFLE_ID);
        assertEq(sId, 2);
        assertEq(t, 1);
        assertEq(mr, newRoot);
        assertEq(pool, 2000 ether);
        assertFalse(active);
        assertEq(vault.totalPoolAllocated(), 2000 ether);
    }

    function test_setRaffleActive() public {
        _createDefaultRaffle();
        vault.setRaffleActive(RAFFLE_ID, false);

        (,,,,,bool active) = vault.getRaffle(RAFFLE_ID);
        assertFalse(active);
    }

    function test_createRaffle_revert_invalidInputs() public {
        vm.expectRevert("RaffleVault: invalid raffle");
        vault.createOrUpdateRaffle(1, 0, 0, merkleRoot, POOL, true); // season 0

        vm.expectRevert("RaffleVault: invalid raffle");
        vault.createOrUpdateRaffle(1, 1, 5, merkleRoot, POOL, true); // tier 5

        vm.expectRevert("RaffleVault: invalid raffle");
        vault.createOrUpdateRaffle(1, 1, 0, bytes32(0), POOL, true); // zero root

        vm.expectRevert("RaffleVault: invalid raffle");
        vault.createOrUpdateRaffle(1, 1, 0, merkleRoot, 0, true); // zero pool
    }

    function test_createRaffle_revert_nonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.createOrUpdateRaffle(1, 1, 0, merkleRoot, POOL, true);
    }

    function test_updateRaffle_revert_poolBelowClaimed() public {
        _createDefaultRaffle();
        _unlockVault();

        // Alice claims 100
        vm.prank(alice);
        vault.claim(RAFFLE_ID, ALICE_AMOUNT, proofAlice);

        // Try to update pool below claimed
        vm.expectRevert("RaffleVault: insufficient pool");
        vault.createOrUpdateRaffle(RAFFLE_ID, SEASON_ID, TIER, merkleRoot, 50 ether, true);
    }

    // ------------------------------------------------------------------
    // Claim
    // ------------------------------------------------------------------

    function test_claim_success() public {
        _createDefaultRaffle();
        _unlockVault();

        vm.expectEmit(true, true, false, true);
        emit RaffleClaimed(alice, RAFFLE_ID, ALICE_AMOUNT);

        vm.prank(alice);
        vault.claim(RAFFLE_ID, ALICE_AMOUNT, proofAlice);

        assertEq(tenx.balanceOf(alice), ALICE_AMOUNT);
        assertTrue(vault.hasClaimed(RAFFLE_ID, alice));

        (, , , , uint256 claimed, ) = vault.getRaffle(RAFFLE_ID);
        assertEq(claimed, ALICE_AMOUNT);
        assertEq(vault.totalClaimedOverall(), ALICE_AMOUNT);
    }

    function test_claim_revert_invalidProof() public {
        _createDefaultRaffle();
        _unlockVault();

        vm.prank(alice);
        vm.expectRevert("RaffleVault: invalid proof");
        vault.claim(RAFFLE_ID, BOB_AMOUNT, proofAlice); // Wrong amount for alice's proof
    }

    function test_claim_revert_inactive() public {
        _createDefaultRaffle();
        vault.setRaffleActive(RAFFLE_ID, false);
        _unlockVault();

        vm.prank(alice);
        vm.expectRevert("RaffleVault: raffle inactive");
        vault.claim(RAFFLE_ID, ALICE_AMOUNT, proofAlice);
    }

    function test_claim_revert_alreadyClaimed() public {
        _createDefaultRaffle();
        _unlockVault();

        vm.prank(alice);
        vault.claim(RAFFLE_ID, ALICE_AMOUNT, proofAlice);

        vm.prank(alice);
        vm.expectRevert("RaffleVault: already claimed");
        vault.claim(RAFFLE_ID, ALICE_AMOUNT, proofAlice);
    }

    function test_claim_revert_locked() public {
        _createDefaultRaffle();
        // Lock is enforced by default, TGE not set

        vm.prank(alice);
        vm.expectRevert("RaffleVault: TGE not set");
        vault.claim(RAFFLE_ID, ALICE_AMOUNT, proofAlice);
    }

    function test_claim_revert_notUnlockedYet() public {
        _createDefaultRaffle();
        uint256 tge = block.timestamp + 1;
        vault.setTGETimestamp(tge);
        vm.warp(tge + 364 days);

        vm.prank(alice);
        vm.expectRevert("RaffleVault: not unlocked yet");
        vault.claim(RAFFLE_ID, ALICE_AMOUNT, proofAlice);
    }

    function test_claim_poolExhausted() public {
        // Create raffle with tiny pool
        vault.createOrUpdateRaffle(RAFFLE_ID, SEASON_ID, TIER, merkleRoot, ALICE_AMOUNT, true);
        _unlockVault();

        // Alice claims the full pool
        vm.prank(alice);
        vault.claim(RAFFLE_ID, ALICE_AMOUNT, proofAlice);

        // Bob can't claim — pool exhausted
        vm.prank(bob);
        vm.expectRevert("RaffleVault: insufficient pool");
        vault.claim(RAFFLE_ID, BOB_AMOUNT, proofBob);
    }

    // ------------------------------------------------------------------
    // Lock / TGE
    // ------------------------------------------------------------------

    function test_setTGE() public {
        uint256 tge = block.timestamp + 1 days;

        vm.expectEmit(false, false, false, true);
        emit TGETimestampSet(tge);

        vault.setTGETimestamp(tge);

        (uint256 ts, bool set) = vault.getTGETimestamp();
        assertEq(ts, tge);
        assertTrue(set);
    }

    function test_setTGE_revert_doubleSet() public {
        vault.setTGETimestamp(block.timestamp + 1 days);

        vm.expectRevert("RaffleVault: TGE already set");
        vault.setTGETimestamp(block.timestamp + 2 days);
    }

    function test_setLockEnforced() public {
        assertTrue(!vault.isUnlocked()); // locked by default

        vm.expectEmit(false, false, false, true);
        emit LockEnforcedUpdated(false);

        vault.setLockEnforced(false);
        assertTrue(vault.isUnlocked());
    }

    function test_isUnlocked_scenarios() public {
        // Default: locked, no TGE
        assertFalse(vault.isUnlocked());

        // TGE set but not elapsed
        uint256 tge = block.timestamp + 1;
        vault.setTGETimestamp(tge);
        assertFalse(vault.isUnlocked());

        // Warp past lock
        vm.warp(tge + 365 days);
        assertTrue(vault.isUnlocked());
    }

    function test_claim_worksWhenLockDisabled() public {
        _createDefaultRaffle();
        vault.setLockEnforced(false);

        vm.prank(alice);
        vault.claim(RAFFLE_ID, ALICE_AMOUNT, proofAlice);
        assertEq(tenx.balanceOf(alice), ALICE_AMOUNT);
    }

    // ------------------------------------------------------------------
    // Rescue
    // ------------------------------------------------------------------

    function test_rescueTokens_nonTENX() public {
        MockTENX otherToken = new MockTENX();
        otherToken.mint(address(vault), 500 ether);

        vm.expectEmit(true, true, false, true);
        emit TokensRescued(address(otherToken), alice, 500 ether);

        vault.rescueTokens(address(otherToken), alice, 500 ether);
        assertEq(otherToken.balanceOf(alice), 500 ether);
    }

    function test_rescueTokens_tenxSurplus() public {
        _createDefaultRaffle();

        // Vault has 10000, pool is 1000 — can rescue surplus
        vault.rescueTokens(address(tenx), owner, 9000 ether);
        assertEq(tenx.balanceOf(address(vault)), 1000 ether);
    }

    function test_rescueTokens_revert_insufficientPool() public {
        _createDefaultRaffle();

        vm.expectRevert("RaffleVault: insufficient pool");
        vault.rescueTokens(address(tenx), owner, 9001 ether);
    }

    function test_rescueTokens_revert_zeroRecipient() public {
        vm.expectRevert("RaffleVault: invalid recipient");
        vault.rescueTokens(address(tenx), address(0), 100 ether);
    }

    function test_rescueTokens_revert_zeroAmount() public {
        vm.expectRevert("RaffleVault: invalid amount");
        vault.rescueTokens(address(tenx), alice, 0);
    }

    // ------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------

    function test_hasClaimed() public {
        _createDefaultRaffle();
        _unlockVault();

        assertFalse(vault.hasClaimed(RAFFLE_ID, alice));

        vm.prank(alice);
        vault.claim(RAFFLE_ID, ALICE_AMOUNT, proofAlice);

        assertTrue(vault.hasClaimed(RAFFLE_ID, alice));
    }

    function test_claimableFor() public {
        _createDefaultRaffle();
        _unlockVault();

        (bool valid, bool claimed) = vault.claimableFor(RAFFLE_ID, alice, ALICE_AMOUNT, proofAlice);
        assertTrue(valid);
        assertFalse(claimed);
    }

    function test_vaultBalance() public view {
        assertEq(vault.vaultBalance(), 10_000 ether);
    }

    function test_getUnlockTime() public {
        assertEq(vault.getUnlockTime(), 0);

        uint256 tge = block.timestamp + 1 days;
        vault.setTGETimestamp(tge);
        assertEq(vault.getUnlockTime(), tge + 365 days);
    }

    // ==================================================================
    // NEW: Raffle management
    // ==================================================================

    function test_createRaffle_raffleIdZero_succeeds() public {
        vault.createOrUpdateRaffle(0, SEASON_ID, TIER, merkleRoot, POOL, true);

        (uint256 sId, uint8 t, bytes32 mr, uint256 pool,, bool active) = vault.getRaffle(0);
        assertEq(sId, SEASON_ID);
        assertEq(t, TIER);
        assertEq(mr, merkleRoot);
        assertEq(pool, POOL);
        assertTrue(active);
    }

    function test_updateRaffle_merkleRootChange() public {
        _createDefaultRaffle();
        _unlockVault();

        // Alice claims with original root
        vm.prank(alice);
        vault.claim(RAFFLE_ID, ALICE_AMOUNT, proofAlice);

        // Update root to something new — old proofs are now invalid
        bytes32 newRoot = keccak256("newRoot");
        vault.createOrUpdateRaffle(RAFFLE_ID, SEASON_ID, TIER, newRoot, POOL, true);

        // Bob's old proof should fail
        vm.prank(bob);
        vm.expectRevert("RaffleVault: invalid proof");
        vault.claim(RAFFLE_ID, BOB_AMOUNT, proofBob);
    }

    function test_setRaffleActive_revert_nonexistent() public {
        vm.expectRevert("RaffleVault: invalid raffle");
        vault.setRaffleActive(999, true);
    }

    function test_setRaffleActive_revert_nonOwner() public {
        _createDefaultRaffle();

        vm.prank(alice);
        vm.expectRevert();
        vault.setRaffleActive(RAFFLE_ID, false);
    }

    function test_setRaffleActive_reactivate() public {
        _createDefaultRaffle();
        _unlockVault();

        vault.setRaffleActive(RAFFLE_ID, false);

        vm.prank(alice);
        vm.expectRevert("RaffleVault: raffle inactive");
        vault.claim(RAFFLE_ID, ALICE_AMOUNT, proofAlice);

        vault.setRaffleActive(RAFFLE_ID, true);

        vm.prank(alice);
        vault.claim(RAFFLE_ID, ALICE_AMOUNT, proofAlice);
        assertEq(tenx.balanceOf(alice), ALICE_AMOUNT);
    }

    function test_getRaffle_nonexistent_returnsDefaults() public view {
        (uint256 sId, uint8 t, bytes32 mr, uint256 pool, uint256 claimed, bool active) = vault.getRaffle(999);
        assertEq(sId, 0);
        assertEq(t, 0);
        assertEq(mr, bytes32(0));
        assertEq(pool, 0);
        assertEq(claimed, 0);
        assertFalse(active);
    }

    function test_createRaffle_tier4_succeeds() public {
        vault.createOrUpdateRaffle(RAFFLE_ID, SEASON_ID, 4, merkleRoot, POOL, true);
        (, uint8 t,,,,) = vault.getRaffle(RAFFLE_ID);
        assertEq(t, 4);
    }

    function test_createRaffle_tier5_reverts() public {
        vm.expectRevert("RaffleVault: invalid raffle");
        vault.createOrUpdateRaffle(RAFFLE_ID, SEASON_ID, 5, merkleRoot, POOL, true);
    }

    function test_totalPoolAllocated_multipleRaffles() public {
        vault.createOrUpdateRaffle(1, 1, 0, merkleRoot, 500 ether, true);
        vault.createOrUpdateRaffle(2, 1, 1, merkleRoot, 300 ether, true);

        assertEq(vault.totalPoolAllocated(), 800 ether);
    }

    function test_updateRaffle_poolIncrease_adjustsTotal() public {
        _createDefaultRaffle(); // pool = 1000
        assertEq(vault.totalPoolAllocated(), POOL);

        vault.createOrUpdateRaffle(RAFFLE_ID, SEASON_ID, TIER, merkleRoot, 2000 ether, true);
        assertEq(vault.totalPoolAllocated(), 2000 ether);
    }

    // ==================================================================
    // NEW: Claiming edge cases
    // ==================================================================

    function test_claim_multipleRaffles_independently() public {
        // Raffle 1 — default
        _createDefaultRaffle();

        // Raffle 2 — same tree, different raffleId
        // Need new leaves with raffleId=2
        uint256 raffle2Id = 2;
        bytes32 leaf0r2 = _makeLeaf(alice, raffle2Id, ALICE_AMOUNT);
        bytes32 leaf1r2 = _makeLeaf(bob, raffle2Id, BOB_AMOUNT);
        bytes32 leaf2r2 = _makeLeaf(carol, raffle2Id, uint256(150 ether));
        bytes32 leaf3r2 = _makeLeaf(dave, raffle2Id, uint256(50 ether));

        bytes32 hash01r2 = _hashPair(leaf0r2, leaf1r2);
        bytes32 hash23r2 = _hashPair(leaf2r2, leaf3r2);
        bytes32 root2 = _hashPair(hash01r2, hash23r2);

        bytes32[] memory proofAliceR2 = new bytes32[](2);
        proofAliceR2[0] = leaf1r2;
        proofAliceR2[1] = hash23r2;

        vault.createOrUpdateRaffle(raffle2Id, 2, 1, root2, POOL, true);
        _unlockVault();

        // Alice claims from raffle 1
        vm.prank(alice);
        vault.claim(RAFFLE_ID, ALICE_AMOUNT, proofAlice);

        // Alice claims from raffle 2
        vm.prank(alice);
        vault.claim(raffle2Id, ALICE_AMOUNT, proofAliceR2);

        assertEq(tenx.balanceOf(alice), ALICE_AMOUNT * 2);
        assertEq(vault.totalClaimedOverall(), ALICE_AMOUNT * 2);
    }

    function test_claim_atExactUnlockTimestamp() public {
        _createDefaultRaffle();
        uint256 tge = block.timestamp + 1;
        vault.setTGETimestamp(tge);
        vm.warp(tge + 365 days); // exactly at boundary

        vm.prank(alice);
        vault.claim(RAFFLE_ID, ALICE_AMOUNT, proofAlice);
        assertEq(tenx.balanceOf(alice), ALICE_AMOUNT);
    }

    function test_claim_oneSecondBeforeUnlock_reverts() public {
        _createDefaultRaffle();
        uint256 tge = block.timestamp + 1;
        vault.setTGETimestamp(tge);
        vm.warp(tge + 365 days - 1);

        vm.prank(alice);
        vm.expectRevert("RaffleVault: not unlocked yet");
        vault.claim(RAFFLE_ID, ALICE_AMOUNT, proofAlice);
    }

    function test_claim_emptyMerkleProof_reverts() public {
        _createDefaultRaffle();
        _unlockVault();

        bytes32[] memory emptyProof = new bytes32[](0);
        vm.prank(alice);
        vm.expectRevert("RaffleVault: invalid proof");
        vault.claim(RAFFLE_ID, ALICE_AMOUNT, emptyProof);
    }

    function test_claim_zeroAmount_reverts() public {
        _createDefaultRaffle();
        _unlockVault();

        vm.prank(alice);
        vm.expectRevert("RaffleVault: invalid amount");
        vault.claim(RAFFLE_ID, 0, proofAlice);
    }

    function test_claim_wrongUser_validProof_reverts() public {
        _createDefaultRaffle();
        _unlockVault();

        // Bob tries to use alice's proof
        vm.prank(bob);
        vm.expectRevert("RaffleVault: invalid proof");
        vault.claim(RAFFLE_ID, ALICE_AMOUNT, proofAlice);
    }

    function test_claim_invalidRaffleId_reverts() public {
        _unlockVault();

        vm.prank(alice);
        vm.expectRevert("RaffleVault: invalid raffle");
        vault.claim(999, ALICE_AMOUNT, proofAlice);
    }

    function test_claim_poolExhausted_twoUsers() public {
        // Create raffle with pool = alice + bob exactly
        uint256 exactPool = ALICE_AMOUNT + BOB_AMOUNT; // 300 ether
        vault.createOrUpdateRaffle(RAFFLE_ID, SEASON_ID, TIER, merkleRoot, exactPool, true);
        _unlockVault();

        vm.prank(alice);
        vault.claim(RAFFLE_ID, ALICE_AMOUNT, proofAlice);

        vm.prank(bob);
        vault.claim(RAFFLE_ID, BOB_AMOUNT, proofBob);

        (, , , , uint256 claimed, ) = vault.getRaffle(RAFFLE_ID);
        assertEq(claimed, exactPool);
    }

    function test_totalClaimedOverall_multipleRafflesMultipleClaims() public {
        // Raffle 1
        _createDefaultRaffle();

        // Raffle 2 with same structure but different raffleId
        uint256 raffle2Id = 2;
        bytes32 leaf0r2 = _makeLeaf(alice, raffle2Id, ALICE_AMOUNT);
        bytes32 leaf1r2 = _makeLeaf(bob, raffle2Id, BOB_AMOUNT);
        bytes32 leaf2r2 = _makeLeaf(carol, raffle2Id, uint256(150 ether));
        bytes32 leaf3r2 = _makeLeaf(dave, raffle2Id, uint256(50 ether));

        bytes32 hash01r2 = _hashPair(leaf0r2, leaf1r2);
        bytes32 hash23r2 = _hashPair(leaf2r2, leaf3r2);
        bytes32 root2 = _hashPair(hash01r2, hash23r2);

        bytes32[] memory proofBobR2 = new bytes32[](2);
        proofBobR2[0] = leaf0r2;
        proofBobR2[1] = hash23r2;

        vault.createOrUpdateRaffle(raffle2Id, 2, 1, root2, POOL, true);
        _unlockVault();

        // Alice claims raffle 1, bob claims raffle 1 and 2
        vm.prank(alice);
        vault.claim(RAFFLE_ID, ALICE_AMOUNT, proofAlice);

        vm.prank(bob);
        vault.claim(RAFFLE_ID, BOB_AMOUNT, proofBob);

        vm.prank(bob);
        vault.claim(raffle2Id, BOB_AMOUNT, proofBobR2);

        assertEq(vault.totalClaimedOverall(), ALICE_AMOUNT + BOB_AMOUNT + BOB_AMOUNT);
    }

    // ==================================================================
    // NEW: TGE & lock
    // ==================================================================

    function test_setTGE_revert_nonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setTGETimestamp(block.timestamp + 1 days);
    }

    function test_setTGE_revert_pastTimestamp() public {
        vm.expectRevert("RaffleVault: TGE must be in future");
        vault.setTGETimestamp(block.timestamp - 1);
    }

    function test_setTGE_revert_currentTimestamp() public {
        vm.expectRevert("RaffleVault: TGE must be in future");
        vault.setTGETimestamp(block.timestamp);
    }

    function test_getTGETimestamp_beforeSet() public view {
        (uint256 ts, bool isSet) = vault.getTGETimestamp();
        assertEq(ts, 0);
        assertFalse(isSet);
    }

    function test_setLockEnforced_revert_nonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.setLockEnforced(false);
    }

    function test_setLockEnforced_reEnable() public {
        vault.setLockEnforced(false);
        assertTrue(vault.isUnlocked());

        vault.setLockEnforced(true);
        assertFalse(vault.isUnlocked());
    }

    // ==================================================================
    // NEW: Rescue extras
    // ==================================================================

    function test_rescueTokens_revert_nonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.rescueTokens(address(tenx), alice, 100 ether);
    }

    function test_rescueTokens_exactSurplus() public {
        _createDefaultRaffle(); // pool = 1000

        // Vault has 10000, unclaimed pool = 1000 → surplus = 9000
        vault.rescueTokens(address(tenx), owner, 9000 ether);
        assertEq(tenx.balanceOf(address(vault)), 1000 ether);
    }

    function test_rescueTokens_afterClaim_freesBalance() public {
        _createDefaultRaffle();
        _unlockVault();

        vm.prank(alice);
        vault.claim(RAFFLE_ID, ALICE_AMOUNT, proofAlice);

        // After alice claims 100, unclaimed pool = 1000 - 100 = 900
        // vault balance = 10000 - 100 = 9900 → surplus = 9900 - 900 = 9000
        vault.rescueTokens(address(tenx), owner, 9000 ether);
        assertEq(tenx.balanceOf(address(vault)), 900 ether);
    }

    // ==================================================================
    // NEW: claimableFor states
    // ==================================================================

    function test_claimableFor_alreadyClaimed() public {
        _createDefaultRaffle();
        _unlockVault();

        vm.prank(alice);
        vault.claim(RAFFLE_ID, ALICE_AMOUNT, proofAlice);

        (bool valid, bool claimed) = vault.claimableFor(RAFFLE_ID, alice, ALICE_AMOUNT, proofAlice);
        assertTrue(valid); // proof is still valid
        assertTrue(claimed); // but already claimed
    }

    function test_claimableFor_inactiveRaffle() public {
        _createDefaultRaffle();
        vault.setRaffleActive(RAFFLE_ID, false);
        _unlockVault();

        (bool valid, bool claimed) = vault.claimableFor(RAFFLE_ID, alice, ALICE_AMOUNT, proofAlice);
        assertFalse(valid);
        assertFalse(claimed);
    }

    function test_claimableFor_lockedVault() public {
        _createDefaultRaffle();
        // lock is enforced, TGE not set

        (bool valid, bool claimed) = vault.claimableFor(RAFFLE_ID, alice, ALICE_AMOUNT, proofAlice);
        assertFalse(valid);
        assertFalse(claimed);
    }
}
