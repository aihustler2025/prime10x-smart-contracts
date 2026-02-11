# 003 — NatSpec Comments

## Summary

Added comprehensive NatSpec documentation to all 4 contracts following Solidity best practices.

## Approach

### Tags Used

| Tag | Usage |
|-----|-------|
| `@title` | Contract-level title |
| `@author` | `Prime10X Team` on all contracts |
| `@notice` | User-facing description (contracts, public/external functions, events) |
| `@dev` | Developer-facing implementation details (internal functions, overrides, storage) |
| `@param` | Every function parameter and event parameter |
| `@return` | Every return value on view/pure functions |
| `@custom:security` | Security-sensitive functions (claim, rescue, one-shot admin) |

### Style

- Consistent `///` single-line style for all NatSpec
- Section headers using `// ------------------------------------------------------------------` dividers
- Every public/external function documented with at minimum `@notice`
- Internal functions documented with `@dev`
- All events documented with `@param` for each parameter
- Custom errors documented with `@dev` describing when they're thrown
- State variables documented with `@notice` (public) or `@dev` (private)

## What Was Added

### Prime10XMarketingVault.sol
- `@author`, expanded `@dev` on contract
- `@param` on all event parameters (Locked, Claimed, TGETimestampSet, DistributorUpdated)
- `@notice`/`@dev` on all state variables
- `@return` on all view functions
- `@custom:security` on `setTGETimestamp`, `claim`, `claimFor`, `rescueTokens`

### Prime10XRaffleVault.sol
- `@author`, expanded `@dev` on contract
- `@param` on all event parameters and struct fields
- `@return` on all view functions including multi-return `getRaffle` and `claimableFor`
- `@custom:security` on `claim`, `setTGETimestamp`, `rescueTokens`

### Prime10XBadgeSBT.sol
- `@author`, expanded `@dev` on contract
- `@dev` on all custom errors (Soulbound, InvalidBadgeType, InvalidSeason, BadgeAlreadyAssigned)
- `@param` on event parameters
- `@return` on `walletOf`, `totalSupply`, `tokenURI`
- `@custom:security` on `mintBadge`
- `@dev` on all soulbound override functions

### Prime10XRewardVoucher.sol
- `@author`, expanded `@dev` on contract
- `@param` on all event parameters
- `@return` on `getVoucherInfo`, `vouchersOf`, `tokenURI`
- `@custom:security` on `redeemVoucher`
- `@dev` on all soulbound override functions and ERC721Enumerable overrides

## Files Changed

- `contracts/Prime10XMarketingVault.sol`
- `contracts/Prime10XRaffleVault.sol`
- `contracts/Prime10XBadgeSBT.sol`
- `contracts/Prime10XRewardVoucher.sol`
