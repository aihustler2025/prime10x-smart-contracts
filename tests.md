# Prime10X Smart Contracts — Test Suite

**210 tests** across 4 contracts. All passing.

```
forge test
Ran 4 test suites: 210 tests passed, 0 failed, 0 skipped (210 total tests)
```

---

## Badge SBT — 36 tests

Non-transferable badge NFTs awarded to users per season.

### Setup

| Test | What it checks |
|------|---------------|
| Constructor | Contract deploys with correct name, symbol, and owner |

### Minting badges

| Test | What it checks |
|------|---------------|
| Mint success | A badge is created for a user with the correct data and fires an event |
| Sequential IDs | Each new badge gets the next ID in order (1, 2, 3...) |
| All badge types | Every valid badge type (0 through 5) can be minted |
| Rejects duplicate | The same user can't receive the same badge type twice in one season |
| Rejects invalid badge type | Badge types outside the valid range are rejected |
| Rejects zero season | Season must be at least 1 |
| Only owner can mint | Non-owners are blocked from minting |
| Rejects zero address | Minting to address(0) reverts |
| Badge type 5 succeeds | Upper boundary badge type (5) works |
| Badge type 255 reverts | Large out-of-range badge type (255) rejected |
| Badge type 6 reverts | Explicit boundary: type 6 is rejected |
| Multiple users same season | Two users get different badge types in same season without collision |
| Same user different seasons | Same user can hold badges across multiple seasons |

### Revoking badges

| Test | What it checks |
|------|---------------|
| Revoke success | Owner can revoke a badge — it gets burned and fires an event |
| Revoke clears data | After revoking, the same badge type can be re-issued to that user |
| Only owner can revoke | Non-owners are blocked from revoking |
| Can't revoke nonexistent | Revoking a badge that doesn't exist is rejected |
| Revoke then remint different type | After revoking, re-minting with a different badge type works |
| ownerOf reverts on revoked | ownerOf() reverts on a revoked (burned) token |
| tokenURI reverts on revoked | tokenURI() reverts on a revoked (burned) token |

### Non-transferable enforcement

| Test | What it checks |
|------|---------------|
| Transfer blocked | Badges cannot be transferred between users |
| Safe transfer (4-arg) blocked | The 4-argument safeTransferFrom is blocked |
| Safe transfer (3-arg) blocked | The 3-argument safeTransferFrom is also blocked |
| Approval blocked | Users cannot approve others to manage their badges |
| Approval-for-all blocked | Blanket approvals are also blocked |
| getApproved returns zero | getApproved() returns address(0) (no approvals possible) |
| isApprovedForAll returns false | Always returns false for any pair of addresses |

### Metadata & views

| Test | What it checks |
|------|---------------|
| Token URI format | Metadata URL follows the expected pattern with season and badge type |
| Token URI season 1 type 0 | Exact URI string for season 1, type 0 |
| URI rejects nonexistent | Requesting the URL for a nonexistent badge fails |
| Wallet lookup | Returns the correct badge ID for a user (or zero if they have none) |
| Wallet lookup nonexistent season | Returns 0 for an unused season |
| Wallet lookup zero address | Returns 0 for zero address |
| Balance tracks correctly | balanceOf tracks correctly across multiple mints and a revoke |
| Total supply tracking | Supply count goes up on mint and down on revoke |

---

## Marketing Vault — 62 tests

Holds TENX tokens for marketing campaigns with a time lock tied to the Token Generation Event (TGE).

### Setup

| Test | What it checks |
|------|---------------|
| Constructor | Contract deploys with correct token address and owner |
| Rejects zero token address | Deploying with no token address fails |

### TGE date configuration

| Test | What it checks |
|------|---------------|
| Set TGE date | Owner can set the TGE timestamp and it fires an event |
| Update TGE date | TGE date can be changed multiple times as timelines shift |
| Rejects past date | TGE date must be in the future |
| Rejects current timestamp | TGE at exact current timestamp fails (must be strictly future) |
| Only owner can set | Non-owners are blocked |

### Distributor role

| Test | What it checks |
|------|---------------|
| Grant distributor | Owner can designate someone as a distributor |
| Revoke distributor | Owner can remove distributor access |
| Rejects zero address | Can't grant the role to an empty address |
| Only owner can manage | Non-owners can't change distributor roles |

### Allocating tokens to users

| Test | What it checks |
|------|---------------|
| Single allocation | Tokens are locked for a user for a specific season, with correct bookkeeping |
| Distributor can allocate | Approved distributors can allocate tokens (not just the owner) |
| Batch allocation | Multiple users can be allocated tokens in one call |
| Batch single item | Batch with 1 element works correctly |
| Batch empty arrays | Batch with empty arrays is a no-op (no revert) |
| Rejects mismatched arrays | User and amount arrays must be the same length |
| Rejects unauthorized caller | Only owner or distributors can allocate |
| Rejects zero address | Can't allocate to an empty address |
| Rejects zero amount | Amount must be greater than zero |
| Rejects zero season | Season must be at least 1 |
| Same user same season accumulates | Two allocations to same user/season add up |
| Revoked distributor can't allocate | Revoked distributor is blocked from allocating |

### Claiming tokens

| Test | What it checks |
|------|---------------|
| Claim success | After the lock period passes, a user receives their tokens |
| Claim blocked before unlock | Users can't claim until the full lock period has elapsed |
| Claim blocked without TGE | Users can't claim if no TGE date has been set |
| Claim blocked with nothing owed | Users with zero balance can't claim |
| Claim at exact unlock timestamp | Claim at exactly TGE + 365 days succeeds (>= boundary) |
| Claim one second before reverts | One second before unlock fails |
| Multiple users sequential | Multiple users claim in sequence, globalLocked reaches 0 |
| Claimed twice reverts | Second claim attempt fails with "nothing to claim" |
| Multi-season event amount | Event amount equals sum of all seasons |
| Multiple seasons then claim | Claim pulls total across all allocated seasons |

### Claiming on behalf of a user

| Test | What it checks |
|------|---------------|
| Owner can claim for user | Owner can trigger a claim that sends tokens to the user |
| Non-owner blocked | Only the owner can claim on someone else's behalf |
| Distributor can't claimFor | Distributor role doesn't grant claimFor access (owner-only) |
| claimFor zero address | claimFor(address(0)) reverts (nothing to claim) |

### Lock enforcement toggle

| Test | What it checks |
|------|---------------|
| Disable lock | Turning off the lock makes tokens immediately claimable |
| Re-enable lock | Lock can be turned back on after being disabled |
| Only owner can toggle | Non-owners are blocked |
| Claim with lock disabled | Users can claim without waiting when the lock is off |
| Enable emits event | setLockEnforced(true) emits event with true value |

### Depositing tokens

| Test | What it checks |
|------|---------------|
| Deposit success | Anyone can deposit TENX tokens into the vault |
| Rejects zero amount | Deposit amount must be greater than zero |
| Rejects no approval | Deposit without ERC20 approval fails |
| Multiple deposits accumulate | Multiple deposits add up in vault balance |

### Rescuing tokens

| Test | What it checks |
|------|---------------|
| Rescue other tokens | Non-TENX tokens sent to the vault by mistake can be recovered |
| Rescue TENX surplus | Excess TENX (above what's owed to users) can be withdrawn |
| Rescue exact surplus | Rescuing exactly balance - globalLocked succeeds |
| Rescue after claim | Freed tokens from claim become rescuable |
| Rescue zero amount | Rescuing 0 tokens succeeds as a no-op |
| Blocks rescue below owed | Can't withdraw TENX if it would leave less than what's locked for users |
| Rejects zero recipient | Must specify a valid destination address |
| Non-owner blocked | Non-owner can't rescue tokens |

### Read-only queries

| Test | What it checks |
|------|---------------|
| Unlock time (no TGE) | Returns zero when TGE hasn't been set yet |
| Unlock time (with TGE) | Returns the correct date (TGE + 365 days) |
| Unlock status progression | Reports locked → unlocked as time passes the threshold |
| Vault balance | Reports the correct token balance held by the vault |
| Unknown user totalLocked | Returns 0 for a fresh address |
| Unknown user totalClaimed | Returns 0 for a fresh address |
| lockedBySeason persists after claim | Per-season amounts still readable after claim (only totalLocked zeroed) |
| Season total across users | seasonTotalLocked sums correctly across multiple users |

---

## Raffle Vault — 60 tests

Manages prize pools for raffles using a Merkle-tree-based claim system with a TGE time lock.

### Setup

| Test | What it checks |
|------|---------------|
| Constructor | Contract deploys with correct token address and owner |
| Rejects zero token address | Deploying with no token address fails |

### Raffle management

| Test | What it checks |
|------|---------------|
| Create raffle | A new raffle is created with the correct settings and fires an event |
| Create raffle ID zero | raffleId 0 works (no restriction) |
| Update raffle | An existing raffle's settings can be changed |
| Update merkle root change | Changing root invalidates old proofs |
| Update pool increase | Increasing pool updates totalPoolAllocated correctly |
| Activate / deactivate | Raffles can be toggled on and off |
| Reactivate raffle | Deactivate then reactivate allows claiming again |
| Rejects invalid inputs | Missing or zero values are rejected when creating a raffle |
| Only owner can create | Non-owners are blocked |
| Update can't reduce pool below claimed | Pool size can't be set lower than what's already been claimed |
| setRaffleActive rejects nonexistent | Can't activate a raffle that doesn't exist |
| setRaffleActive rejects non-owner | Non-owner blocked from toggling raffle active |
| getRaffle nonexistent | Returns all zeros for an unused raffle ID |
| Tier 4 succeeds | Upper tier boundary (4 = Diamond) works |
| Tier 5 reverts | One past boundary (tier 5) fails |
| Total pool across raffles | totalPoolAllocated sums across multiple raffles |

### Claiming prizes

| Test | What it checks |
|------|---------------|
| Claim success | A valid winner can claim their prize with a correct proof |
| Rejects invalid proof | A tampered or wrong proof is rejected |
| Rejects inactive raffle | Can't claim from a deactivated raffle |
| Rejects double claim | The same winner can't claim twice |
| Rejects when locked (no TGE) | Claims are blocked while the time lock is active and TGE not set |
| Rejects when not unlocked yet | Claims are blocked before the TGE lock period ends |
| Pool exhausted | Claiming fails when the pool runs out of tokens |
| Works when lock disabled | Claims go through immediately when the lock is turned off |
| Multiple raffles independently | User claims from two separate raffles |
| Claim at exact unlock timestamp | Boundary: claim at TGE + 365 days succeeds |
| One second before unlock reverts | One second early fails |
| Empty merkle proof reverts | Empty proof array rejected |
| Zero amount reverts | Zero claim amount rejected |
| Wrong user valid proof reverts | Bob using Alice's proof fails |
| Invalid raffle ID reverts | Nonexistent raffle ID rejected |
| Pool exhausted by two users | Two users deplete pool exactly, bookkeeping correct |
| Total claimed across raffles | totalClaimedOverall tracks across multiple raffles and claims |

### TGE & lock settings

| Test | What it checks |
|------|---------------|
| Set TGE date | Owner can set the TGE timestamp |
| Rejects double TGE set | TGE can only be set once |
| Rejects non-owner TGE | Non-owner blocked from setting TGE |
| Rejects past timestamp | Past timestamp rejected |
| Rejects current timestamp | Current timestamp rejected (must be future) |
| getTGETimestamp before set | Returns (0, false) initially |
| Toggle lock | Lock enforcement can be enabled or disabled |
| Re-enable lock | Disable then re-enable works correctly |
| Lock toggle rejects non-owner | Non-owner blocked from toggling lock |
| Unlock status scenarios | Reports correct locked/unlocked status across different states |
| Unlock time | Returns the correct unlock date |

### Rescuing tokens

| Test | What it checks |
|------|---------------|
| Rescue other tokens | Non-TENX tokens can be recovered |
| Rescue TENX surplus | Excess TENX above what's needed for prizes can be withdrawn |
| Rescue exact surplus | Rescuing exactly the surplus amount succeeds |
| Rescue after claim | Claimed amount becomes rescuable |
| Blocks rescue below pools | Can't withdraw TENX needed to cover active raffle pools |
| Rejects zero recipient | Must specify a valid destination |
| Rejects zero amount | Amount must be greater than zero |
| Non-owner blocked | Non-owner can't rescue tokens |

### Read-only queries

| Test | What it checks |
|------|---------------|
| Has claimed | Correctly reports whether a user has already claimed |
| Claimable for valid user | Returns (valid=true, claimed=false) for unclaimed valid proof |
| Claimable for already claimed | Returns (valid=true, claimed=true) for valid proof + claimed user |
| Claimable for inactive raffle | Returns (false, false) for inactive raffle |
| Claimable for locked vault | Returns (false, false) when vault is locked |
| Vault balance | Reports the correct token balance in the vault |

---

## Reward Voucher — 52 tests

Soulbound NFT vouchers representing a claim to locked TENX tokens, redeemable after a configurable date.

### Setup

| Test | What it checks |
|------|---------------|
| Constructor | Contract deploys with correct name, symbol, and owner |

### Minting vouchers

| Test | What it checks |
|------|---------------|
| Mint success | A voucher is created with the correct amount, season, and owner |
| Sequential IDs | Each new voucher gets the next ID in order |
| Only owner can mint | Non-owners are blocked |
| Rejects zero address | Must specify a valid recipient |
| Rejects zero amount | Token amount must be greater than zero |
| Rejects zero season | Season must be at least 1 |
| Multiple same user same season | Same user can get multiple vouchers in same season |
| Large TENX amount | Extreme uint256 value stores correctly |

### Redeeming vouchers

| Test | What it checks |
|------|---------------|
| Redeem success | After the claim date passes, the voucher holder can redeem and burn it |
| Rejects when claims not enabled | Can't redeem if no claim date has been set |
| Rejects before claim date | Can't redeem if the claim date hasn't arrived yet |
| Rejects non-holder | Only the voucher owner can redeem it |
| Rejects nonexistent voucher | Redeeming a voucher that doesn't exist fails |
| Redeem at exact claim date | Boundary: redeem at exactly the enable date succeeds |
| One second before reverts | One second before claim date fails |
| Redeem after date update | Updating date to past makes voucher immediately redeemable |
| Correct event data | Event has correct tenxAmount and seasonId |

### Revoking vouchers

| Test | What it checks |
|------|---------------|
| Revoke success | Owner can revoke and burn a voucher |
| Only owner can revoke | Non-owners are blocked |
| Can't revoke after redeem | A voucher that's been redeemed can't also be revoked |
| Rejects nonexistent voucher | Revoking a voucher that doesn't exist fails |
| Enumeration correct after revoke | vouchersOf returns correct IDs after revoking middle voucher |
| Revoke then mint gets new ID | New mint gets next sequential ID, not reused |

### Claim date configuration

| Test | What it checks |
|------|---------------|
| Set claim date | Owner can set the date when redemptions open, with an event |
| Update claim date | The date can be changed as timelines shift |
| Rejects zero date | A date of zero is not valid |
| Only owner can set | Non-owners are blocked |
| Not redeemable by default | Redemptions are closed until a claim date is configured |
| Becomes redeemable | Redemptions open once the claim date arrives |
| Multiple updates latest matters | Only the latest set value is active |
| Past date succeeds | Past date allowed (makes immediately redeemable) |

### Non-transferable enforcement

| Test | What it checks |
|------|---------------|
| Transfer blocked | Vouchers cannot be transferred between users |
| Safe transfer blocked | The safe transfer method is also blocked |
| Approval blocked | Users cannot approve others to manage their vouchers |
| Approval-for-all blocked | Blanket approvals are also blocked |

### Metadata

| Test | What it checks |
|------|---------------|
| Set base URI | Owner can set the base URL for voucher metadata |
| Token URI format | Full metadata URL follows the pattern `{base}/{season}/{id}.json` |
| Empty URI when no base | Returns empty string if no base URL is configured |
| URI rejects nonexistent | Requesting the URL for a nonexistent voucher fails |
| Set empty base URI | Clearing base URI returns empty tokenURI |
| Set base URI rejects non-owner | Non-owner blocked from setting base URI |
| Different seasons produce correct URIs | Different seasons produce different correct URI paths |

### Enumeration & interface

| Test | What it checks |
|------|---------------|
| List user's vouchers | Returns all voucher IDs owned by a given user |
| Empty result for new user | Returns empty array for user with no vouchers |
| Empty after all redeemed | Returns empty after all vouchers redeemed |
| Balance tracks correctly | balanceOf tracks mints, revokes, and redeems |
| Total supply tracking | Supply count goes up on mint and down on redeem/revoke |
| Interface support | Contract correctly reports support for ERC-721 and related standards |
| Unsupported interface returns false | Returns false for 0xffffffff and random interface IDs |

### View edge cases

| Test | What it checks |
|------|---------------|
| getVoucherInfo after redeem reverts | Info query on redeemed (burned) token reverts |
| getVoucherInfo after revoke reverts | Info query on revoked (burned) token reverts |
