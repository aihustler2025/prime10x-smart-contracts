# 004 — Test Suite

## Summary

Created a comprehensive Foundry test suite with 106 tests across 4 test files and 1 mock contract.

## Test Structure

```
test/
├── mocks/
│   └── MockTENX.sol              # ERC20 mock with public mint()
├── Prime10XBadgeSBT.t.sol        # 20 tests
├── Prime10XMarketingVault.t.sol  # 32 tests
├── Prime10XRaffleVault.t.sol     # 29 tests
└── Prime10XRewardVoucher.t.sol   # 25 tests
```

## MockTENX

Simple ERC20 contract extending OpenZeppelin's `ERC20` with a public `mint(address, uint256)` function. Used by both vault test suites to fund vaults and verify token transfers.

## Test Coverage by Contract

### Prime10XBadgeSBT (20 tests)

| Category | Tests | Description |
|----------|-------|-------------|
| Deploy | 1 | Constructor sets name, symbol, owner, zero supply |
| Minting | 5 | Success with events, sequential IDs, all badge types, reverts on non-owner/zero-season/invalid-type/duplicate |
| Revoke | 4 | Success with events, clears mappings (allows remint), reverts on non-owner/nonexistent |
| Soulbound | 4 | transferFrom, safeTransferFrom, approve, setApprovalForAll all revert |
| Metadata | 2 | tokenURI format, revert on nonexistent |
| Views | 2 | walletOf returns 0 for none, totalSupply tracks correctly |

### Prime10XMarketingVault (32 tests)

| Category | Tests | Description |
|----------|-------|-------------|
| Deploy | 2 | Constructor sets token/owner, reverts on zero address |
| TGE | 4 | Set once with event, reverts on double-set/past-timestamp/non-owner |
| Distributors | 4 | Grant/revoke with events, reverts on zero-address/non-owner |
| Allocation | 7 | Single + batch success with events, distributor can allocate, reverts on unauthorized/zero-inputs/length-mismatch |
| Claim | 4 | Success after unlock (vm.warp), reverts before unlock/TGE-not-set/nothing-to-claim |
| ClaimFor | 2 | Owner can claim for user, non-owner reverts |
| Rescue | 4 | Non-TENX freely rescued, TENX surplus OK, TENX below locked reverts, zero recipient reverts |
| Views | 5 | getUnlockTime (no TGE / with TGE), isUnlocked progression, vaultBalance |

### Prime10XRaffleVault (29 tests)

| Category | Tests | Description |
|----------|-------|-------------|
| Deploy | 2 | Constructor sets token/owner, reverts on zero token |
| Raffle mgmt | 6 | Create with event, update, activate/deactivate, reverts on invalid inputs/non-owner/pool-below-claimed |
| Claim | 6 | Valid proof success, reverts on invalid-proof/inactive/already-claimed/locked/pool-exhausted |
| Lock/TGE | 5 | Set TGE with event, double-set reverts, toggle lock, isUnlocked scenarios, claim works when lock disabled |
| Rescue | 5 | Non-TENX free, TENX surplus OK, reverts on insufficient-pool/zero-recipient/zero-amount |
| Views | 5 | hasClaimed, claimableFor, vaultBalance, getUnlockTime |

**Merkle tree approach:** Built a 4-leaf tree in `setUp()` with hardcoded leaves for alice, bob, carol, and dave. Proofs are computed manually using `_hashPair` (sorted pair hashing matching OpenZeppelin's `MerkleProof.verify`).

### Prime10XRewardVoucher (25 tests)

| Category | Tests | Description |
|----------|-------|-------------|
| Deploy | 1 | Constructor sets name/symbol/owner |
| Minting | 5 | Success with events, sequential IDs, reverts on non-owner/zero-address/zero-amount/zero-season |
| Redeem | 3 | Burns NFT with events, reverts on non-holder/nonexistent |
| Revoke | 4 | Owner burns with events, reverts on non-owner/already-redeemed/nonexistent |
| Soulbound | 4 | transferFrom, safeTransferFrom, approve, setApprovalForAll all revert |
| Metadata | 4 | setBaseURI with event, tokenURI format, empty when no base, revert on nonexistent |
| Enumeration | 2 | vouchersOf returns correct IDs, totalSupply tracks mint/burn |
| Interface | 1 | supportsInterface for ERC721, ERC721Enumerable, ERC165 |

## Running Tests

```bash
# Run all tests
forge test

# Verbose output
forge test -vvv

# Run specific test file
forge test --match-path test/Prime10XBadgeSBT.t.sol

# Run specific test
forge test --match-test test_claim_success
```

## Results

```
Ran 4 test suites: 106 tests passed, 0 failed, 0 skipped
```

## Files Created

- `test/mocks/MockTENX.sol`
- `test/Prime10XBadgeSBT.t.sol`
- `test/Prime10XMarketingVault.t.sol`
- `test/Prime10XRaffleVault.t.sol`
- `test/Prime10XRewardVoucher.t.sol`
