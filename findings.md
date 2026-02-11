# Prime10X Smart Contracts — Security Findings

**Date:** 2026-02-11
**Solidity:** 0.8.28 / OpenZeppelin v5.5.0
**Methodology:** Manual review cross-referenced against 2025-2026 exploit patterns

---

## Summary

| Severity | Count | Fixed | Acknowledged |
|----------|-------|-------|-------------|
| Medium | 3 | 3 | 0 |
| Low | 10 | 3 | 7 |
| Informational | 10 | 0 | 10 |

---

## Fixed Findings

### F-01. Merkle leaf second-preimage vulnerability [Medium] [FIXED]

**Contract:** `Prime10XRaffleVault.sol`
**Lines:** 209, 259

**Description:** Merkle leaves were single-hashed using `keccak256(abi.encodePacked(msg.sender, raffleId, tenxAmount))`. Without double-hashing, an internal Merkle tree node (64 bytes — two concatenated 32-byte hashes) could potentially be reinterpreted as a valid leaf, allowing an attacker to forge a claim proof from the tree's internal structure.

This is a well-documented attack vector (OpenZeppelin Issue #3091, RareSkills research). OpenZeppelin's own `MerkleProof` documentation recommends double-hashing leaves to prevent second-preimage attacks.

**Fix applied:** Changed to double-hashed leaves with `abi.encode` (which also eliminates any `abi.encodePacked` ambiguity):
```solidity
bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(msg.sender, raffleId, tenxAmount))));
```
Applied in both `claim()` and `claimableFor()`.

---

### F-02. Allocations not backed by actual token balance [Medium] [FIXED]

**Contract:** `Prime10XMarketingVault.sol`
**Function:** `_allocate()`

**Description:** The `_allocate` function incremented `_globalLocked` without verifying the vault actually held enough TENX tokens to cover the allocation. An owner or distributor could allocate arbitrary amounts exceeding the vault's balance. Users would see non-zero `totalLockedOf` balances but `claim()` would revert when `transfer()` fails due to insufficient funds — a silent denial-of-service.

**Fix applied:** Added balance validation before incrementing state:
```solidity
require(_globalLocked + amount <= tenxToken.balanceOf(address(this)), "MarketingVault: vault underfunded");
```

---

### F-03. `rescueTokens` missing `nonReentrant` + unclear underflow [Medium] [FIXED]

**Contract:** `Prime10XMarketingVault.sol`
**Function:** `rescueTokens()`

**Description:** Two issues:
1. `rescueTokens` made an external call to `erc20.transfer()` without `nonReentrant` protection. A malicious ERC20 token (passed as the `token` parameter) could re-enter `rescueTokens` during the transfer, potentially draining more than intended. The `RaffleVault.rescueTokens` correctly included `nonReentrant` — this was an inconsistency.
2. The arithmetic `erc20.balanceOf(address(this)) - amount` would revert with an opaque arithmetic underflow panic if `amount` exceeded balance, rather than a descriptive error.

**Fix applied:** Added `nonReentrant` modifier and explicit balance check:
```solidity
function rescueTokens(...) external onlyOwner nonReentrant {
    ...
    uint256 balance = erc20.balanceOf(address(this));
    require(balance >= amount, "MarketingVault: insufficient balance");
    require(balance - amount >= _globalLocked, "MarketingVault: insufficient TENX balance");
}
```

---

### F-04. Single-step ownership transfer [Low] [FIXED]

**Contracts:** All four contracts

**Description:** All contracts used OpenZeppelin's `Ownable`, which provides a single-step `transferOwnership`. A mistaken call to `transferOwnership(wrongAddress)` permanently and irreversibly loses admin control. OpenZeppelin v5 provides `Ownable2Step` which requires the new owner to call `acceptOwnership()`, preventing accidental transfers.

**Fix applied:** Upgraded all four contracts from `Ownable` to `Ownable2Step`.

---

## Acknowledged Findings

### A-01. Per-season locked amounts not cleared on claim [Low]

**Contract:** `Prime10XMarketingVault.sol`
**Function:** `_claimTo()`

**Description:** When a user claims, `_totalLocked[user]` is zeroed and `_globalLocked` is decremented, but `_lockedBySeason[user][seasonId]` and `_seasonTotalLocked[seasonId]` are NOT cleared. After claiming:
- `lockedBySeason(alice, 1)` still returns the original allocation amount
- `seasonTotalLocked(1)` still includes the claimed amount

Any off-chain system relying on these values for "currently locked" accounting will get stale data. These values effectively represent "ever allocated" rather than "currently locked."

**Note:** Fixing this requires tracking which seasons a user has allocations in (either an array or a sentinel), which adds storage complexity. The current behavior is acceptable if documented — these are historical/audit views, not live accounting.

---

### A-02. Fee-on-transfer token compatibility [Low]

**Contract:** `Prime10XMarketingVault.sol`
**Function:** `depositTokens()`

**Description:** `depositTokens` uses `transferFrom` and emits the requested `amount` in the event without measuring the actual balance change. If TENX were ever a fee-on-transfer token, the vault would receive fewer tokens than recorded, creating a deficit.

**Note:** TENX is set as an `immutable` standard ERC20. This is only relevant if the TENX token itself has transfer fees, which it does not. No fix needed for current deployment, but worth noting for future integrations.

---

### A-03. `_safeMint` callback ordering [Low]

**Contracts:** `Prime10XBadgeSBT.sol`, `Prime10XRewardVoucher.sol`
**Functions:** `mintBadge()`, `mintVoucher()`

**Description:** Both contracts call `_safeMint`, which triggers `onERC721Received` on the recipient if it's a contract. In `BadgeSBT`, the `_totalSupply` increment happens after `_safeMint`. In `RewardVoucher`, the state is set before mint but there's no `nonReentrant`.

**Note:** Both functions are `onlyOwner`, so exploitation requires the owner to deliberately mint to a malicious contract. The duplicate-badge guard (`_seasonBadgeOf` check) holds even under reentrancy. Risk is negligible.

---

### A-04. No mechanism to reduce/revoke allocations [Low]

**Contract:** `Prime10XMarketingVault.sol`

**Description:** Once tokens are allocated via `allocateLockedTokens`, there is no function to reduce or cancel the allocation. If an allocation is made in error, the tokens are permanently committed until the user claims them.

**Note:** This is a design trade-off — immutable allocations provide stronger user guarantees. A `revokeAllocation` function could be added but would weaken user trust.

---

### A-05. Raffle existence relies on `totalTenxPool > 0` [Low]

**Contract:** `Prime10XRaffleVault.sol`

**Description:** The contract uses `raffle.totalTenxPool > 0` as the implicit check for whether a raffle exists (lines 141, 164, 198). There is no explicit `exists` boolean. If future code somehow set `totalTenxPool` to 0 for an existing raffle, `_totalPoolAllocated` would become desynced.

**Note:** Currently safe because `require(totalTenxPool > 0)` prevents creating zero-pool raffles. The invariant holds but is implicit rather than explicit.

---

### A-06. `vouchersOf` unbounded loop [Low]

**Contract:** `Prime10XRewardVoucher.sol`
**Function:** `vouchersOf()`

**Description:** `vouchersOf` iterates over all tokens owned by a user. If a user accumulates thousands of vouchers, this view function could exceed the block gas limit when called from another contract on-chain. Off-chain `eth_call` requests (which most frontends use) have no practical gas limit.

**Note:** This function is intended for off-chain consumption. On-chain consumers should use `tokenOfOwnerByIndex` with pagination instead.

---

### A-07. `getVoucherInfo` reverts for burned tokens despite preserved state [Low]

**Contract:** `Prime10XRewardVoucher.sol`
**Function:** `getVoucherInfo()`

**Description:** After a voucher is burned (via redeem or revoke), `_redeemed[tokenId]` is intentionally preserved for historical queries. However, `getVoucherInfo` requires `_ownerOf(tokenId) != address(0)` and reverts for burned tokens, making the preserved `_redeemed` flag inaccessible through the contract's public interface.

**Note:** A separate `isRedeemed(uint256 tokenId)` view function that doesn't require token existence could be added if historical query access is needed.

---

### A-08. `BADGE_TYPE_MIN` constant is redundant [Informational]

**Contract:** `Prime10XBadgeSBT.sol`

**Description:** `BADGE_TYPE_MIN` is 0, and `badgeType` is `uint256`, so the check `badgeType < BADGE_TYPE_MIN` is always false. The only effective check is `badgeType > BADGE_TYPE_MAX`. The constant exists as a placeholder but adds dead code.

---

### A-09. `_totalSupply` decrement in `unchecked` block [Informational]

**Contract:** `Prime10XBadgeSBT.sol`
**Function:** `revokeBadge()`

**Description:** `_totalSupply -= 1` is in an `unchecked` block. If `_totalSupply` were ever 0 when `revokeBadge` is called, this would silently underflow. In practice this cannot happen because `ownerOf(tokenId)` reverts for non-existent tokens, and every existing token implies `_totalSupply >= 1`. The gas savings are negligible for a single decrement.

---

### A-10. `setRaffleActive` reuses `RaffleConfigured` event [Informational]

**Contract:** `Prime10XRaffleVault.sol`

**Description:** `setRaffleActive` emits the full `RaffleConfigured` event (with all raffle parameters) when only the `active` flag changes. Off-chain indexers may interpret this as a full reconfiguration rather than a simple toggle.

---

### A-11. `claimableFor` returns `valid=true` when already claimed [Informational]

**Contract:** `Prime10XRaffleVault.sol`

**Description:** `claimableFor` returns `valid=true` for a user with a valid Merkle proof even if they've already claimed. The `alreadyClaimed` field must be checked separately. While the function signature makes this clear, front-end developers might check only `valid` and show incorrect UI state.

---

### A-12. Season badge zero-collision after revocation [Informational]

**Contract:** `Prime10XBadgeSBT.sol`

**Description:** `_seasonBadgeOf[to][season]` stores tokenIds and uses `!= 0` to detect assignment. After revocation, the mapping resets to 0, which is indistinguishable from "never had a badge." The `walletOf()` view returns 0 in both cases. This is correct behavior (revoke enables re-issue) but means there's no on-chain way to distinguish "revoked" from "never assigned" without checking events.

---

### A-13. No deposit tracking on RaffleVault [Informational]

**Contract:** `Prime10XRaffleVault.sol`

**Description:** Unlike `MarketingVault` which has a `depositTokens` function with an event, `RaffleVault` relies on direct token transfers for funding. There is no deposit function or event to track funding on-chain.

---

### A-14. Inconsistent TGE setter behavior across contracts [Informational]

**Contracts:** `MarketingVault` vs `RaffleVault`

**Description:** The two vaults handle TGE differently:
- `MarketingVault.setTGETimestamp`: Can be called multiple times, must be future
- `RaffleVault.setTGETimestamp`: One-shot only (`require(!_tgeSet)`), must be future

This is intentional — the marketing vault needs flexibility to adjust timelines while the raffle vault provides stronger guarantees — but should be documented to avoid administrator confusion.

---

## Attack Vectors Checked (2025-2026 Research)

| Attack Vector | Relevant? | Result |
|---|---|---|
| Merkle second-preimage (OZ #3091) | Yes | **Fixed (F-01)** |
| Stale cached state (Yearn $9M, Dec 2025) | Yes | Acknowledged (A-01) |
| Reentrancy — classic + cross-function | Yes | Protected via `nonReentrant` + CEI. **Fixed gap (F-03)** |
| Read-only reentrancy | Low | No external view consumers identified |
| Admin key abuse (zkSync $5M, Apr 2025) | N/A | Owner-trust findings excluded per scope |
| Integer overflow in custom math (Cetus $223M, May 2025) | Checked | Only 2 `unchecked` blocks, both safe |
| Rounding error amplification (Balancer $128M, Nov 2025) | N/A | No exchange rates or division |
| Fee-on-transfer tokens | Yes | Acknowledged (A-02) |
| Flash loan / MEV | Low | No AMM/oracle/price dependencies |
| Unbounded loops / gas griefing | Yes | Acknowledged (A-06) |
| Soulbound token bypass | Yes | Comprehensive — all transfer paths blocked |
| ERC20 return value handling | Yes | Uses `require(transfer(...))` — safe for standard tokens |
| Single-step ownership loss | Yes | **Fixed (F-04)** |
| Supply-chain / frontend attacks (Bybit $1.5B) | N/A | Out of scope (off-chain) |
| ERC-4626 vault inflation | N/A | No vault share tokens |
| Signature replay | N/A | No signatures used |
| Proxy storage collision | N/A | No proxies used |
