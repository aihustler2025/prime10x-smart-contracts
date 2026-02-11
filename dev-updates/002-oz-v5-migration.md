# 002 — OpenZeppelin v5.5.0 Migration

## Summary

Migrated all 4 contracts from OpenZeppelin v4.x patterns to v5.5.0 APIs.

## Changes by Contract

### Prime10XMarketingVault.sol

| Change | Before (v4) | After (v5) |
|--------|-------------|-------------|
| ReentrancyGuard import | `security/ReentrancyGuard.sol` | `utils/ReentrancyGuard.sol` |
| Constructor | `constructor(address tenxToken_)` | `constructor(address tenxToken_) Ownable(msg.sender)` |

### Prime10XRaffleVault.sol

| Change | Before (v4) | After (v5) |
|--------|-------------|-------------|
| ReentrancyGuard import | `security/ReentrancyGuard.sol` | `utils/ReentrancyGuard.sol` |

Constructor already used v5-style `Ownable(owner_)` — no change needed.

### Prime10XBadgeSBT.sol

| Change | Before (v4) | After (v5) |
|--------|-------------|-------------|
| Counters | `using Counters for Counters.Counter` + `_tokenIdTracker` | `uint256 private _nextTokenId` with `++_nextTokenId` |
| Constructor | `constructor() ERC721(...)` | `constructor() ERC721(...) Ownable(msg.sender)` |
| Token existence | `_requireMinted(tokenId)` | `_requireOwned(tokenId)` |
| Transfer hook | `_beforeTokenTransfer(from, to, tokenId, batchSize)` | `_update(to, tokenId, auth) returns (address)` |
| Soulbound check | Check `from` and `to` in `_beforeTokenTransfer` | Check `_ownerOf(tokenId)` and `to` in `_update` |
| safeTransferFrom(3 args) | Override (was virtual in v4) | Removed (not virtual in v5; delegates to 4-arg version) |

### Prime10XRewardVoucher.sol

| Change | Before (v4) | After (v5) |
|--------|-------------|-------------|
| Counters | `using Counters for Counters.Counter` + `_tokenIdTracker` | `uint256 private _nextTokenId` with `++_nextTokenId` |
| ReentrancyGuard import | `security/ReentrancyGuard.sol` | `utils/ReentrancyGuard.sol` |
| Token existence | `_exists(tokenId)` | `_ownerOf(tokenId) != address(0)` |
| Transfer hook | `_beforeTokenTransfer(from, to, tokenId, batchSize)` | `_update(to, tokenId, auth) returns (address)` override on `ERC721Enumerable` |
| New required override | N/A | `_increaseBalance(address, uint128)` override for `ERC721Enumerable` |
| Soulbound overrides | `override` (unqualified) | `override(ERC721, IERC721)` (explicit dual override) |
| safeTransferFrom(3 args) | Override (was virtual in v4) | Removed (not virtual in v5) |
| supportsInterface | `override(ERC721Enumerable, ERC721)` | `override(ERC721Enumerable)` |
| tokenURI | `override` | `override(ERC721)` |
| _burn | Explicit `override(ERC721)` with data cleanup | Removed — v5 burn goes through `_update`; data cleanup handled by voucher lifecycle functions |
| IERC721 import | Not needed | Added explicit import for override specifiers |

## Key Migration Notes

1. **Counters library removed in OZ v5** — replaced with plain `uint256` counter using pre-increment (`++_nextTokenId`).

2. **`_beforeTokenTransfer` → `_update`** — OZ v5 consolidated transfer hooks into `_update(to, tokenId, auth)`. The function returns the previous owner (`from`), which must be obtained via `_ownerOf(tokenId)` inside the override.

3. **`_exists()` removed** — replaced with `_ownerOf(tokenId) != address(0)`.

4. **`_requireMinted()` → `_requireOwned()`** — renamed in v5 for clarity.

5. **`safeTransferFrom(address, address, uint256)` no longer virtual** — in v5 this 3-arg version simply delegates to the 4-arg version. Soulbound enforcement is still effective because `_update` is overridden.

6. **`ReentrancyGuard` moved** — from `security/` to `utils/` in v5.

7. **`Ownable` constructor requires initial owner** — v5 `Ownable(address)` constructor is mandatory.

## Files Changed

- `contracts/Prime10XMarketingVault.sol`
- `contracts/Prime10XRaffleVault.sol`
- `contracts/Prime10XBadgeSBT.sol`
- `contracts/Prime10XRewardVoucher.sol`
