# 005 — Contract Modifications Per Doc

## Summary

Applied contract modifications based on client requirements document. Changes affect Prime10XMarketingVault and Prime10XRewardVoucher. Badge SBT and Raffle Vault remain unchanged (deploy as-is / skip for now).

## Changes by Contract

### Prime10XMarketingVault.sol

| Change | Before | After |
|--------|--------|-------|
| `setTGETimestamp()` | One-shot (`require(!tgeSet)`) | Updatable — can be called multiple times (must still be in the future) |
| Lock enforcement | No bypass mechanism | Added `_lockEnforced` (default `true`) with `setLockEnforced(bool)` for emergency unlock |
| Deposit function | None — vault funded via direct token transfer | Added `depositTokens(uint256 amount)` with `transferFrom` pattern |
| `isUnlocked()` | Only checked `tgeSet && block.timestamp >= tgeTimestamp + LOCK_DURATION` | Also returns `true` if `_lockEnforced == false` |
| `_claimTo()` | Had separate `require(tgeSet, "TGE not set")` check | Removed — unified into single `require(isUnlocked())` check |

#### New State Variables

- `bool private _lockEnforced = true` — global lock toggle

#### New Events

- `LockEnforcedUpdated(bool enforced)` — emitted when lock toggle changes
- `TokensDeposited(address indexed depositor, uint256 amount)` — emitted on deposits

#### New Functions

- `setLockEnforced(bool enforced) external onlyOwner` — enables/disables time lock
- `depositTokens(uint256 amount) external` — deposits TENX via `transferFrom`

### Prime10XRewardVoucher.sol

| Change | Before | After |
|--------|--------|-------|
| `redeemVoucher()` | No time gating — redeemable anytime | Gated by `isRedeemable()` — requires claim enable date set and passed |

#### New State Variables

- `uint256 public claimEnableDate` — timestamp after which vouchers can be redeemed
- `bool public claimEnableDateSet` — whether the claim date has been configured

#### New Events

- `ClaimEnableDateSet(uint256 claimEnableDate)` — emitted when claim date is set/updated

#### New Functions

- `setClaimEnableDate(uint256 claimEnableDate_) external onlyOwner` — sets or updates the claim enable date (updatable, must be > 0)
- `isRedeemable() public view returns (bool)` — returns whether voucher redemptions are currently allowed

### Prime10XBadgeSBT.sol

No changes. Deploy as-is per client document.

### Prime10XRaffleVault.sol

No changes. Skipped per client document (already built).

## Test Updates

Updated test suite from 106 to 120 tests to cover new functionality.

### Prime10XMarketingVault.t.sol (32 → 38 tests)

| Change | Description |
|--------|-------------|
| Replaced | `test_setTGE_revert_doubleSet` → `test_setTGE_canUpdate` (TGE now updatable) |
| Updated | `test_claim_revert_tgeNotSet` error message from "TGE not set" to "not unlocked yet" |
| Added | `test_setLockEnforced_disable` — disabling lock makes vault immediately unlocked |
| Added | `test_setLockEnforced_reEnable` — re-enabling lock after disable |
| Added | `test_setLockEnforced_revert_nonOwner` — access control |
| Added | `test_claim_lockDisabled` — claim succeeds without TGE when lock disabled |
| Added | `test_depositTokens` — deposit via transferFrom with event |
| Added | `test_depositTokens_revert_zeroAmount` — zero amount rejected |

### Prime10XRewardVoucher.t.sol (25 → 33 tests)

| Change | Description |
|--------|-------------|
| Updated | `test_redeemVoucher_success` — now sets claim date before redeeming |
| Updated | `test_redeemVoucher_revert_nonHolder` — sets claim date for proper test isolation |
| Updated | `test_revokeVoucher_revert_alreadyRedeemed` — sets claim date before redeeming |
| Updated | `test_totalSupply_tracksMintBurn` — sets claim date before redeeming |
| Added | `test_redeemVoucher_revert_claimsNotEnabled` — reverts when no claim date set |
| Added | `test_redeemVoucher_revert_claimDateNotPassed` — reverts when date not yet reached |
| Added | `test_setClaimEnableDate` — sets date with event |
| Added | `test_setClaimEnableDate_canUpdate` — date is updatable |
| Added | `test_setClaimEnableDate_revert_zeroDate` — zero date rejected |
| Added | `test_setClaimEnableDate_revert_nonOwner` — access control |
| Added | `test_isRedeemable_defaultFalse` — false by default |
| Added | `test_isRedeemable_trueAfterDate` — becomes true once date passes |

## Results

```
Ran 4 test suites: 120 tests passed, 0 failed, 0 skipped
```

## Files Changed

- `contracts/Prime10XMarketingVault.sol`
- `contracts/Prime10XRewardVoucher.sol`
- `test/Prime10XMarketingVault.t.sol`
- `test/Prime10XRewardVoucher.t.sol`
