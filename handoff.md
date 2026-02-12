# Prime10X Contract Handoff Guide

## What Gets Deployed

| Contract | Constructor Args | Purpose |
| --- | --- | --- |
| **BadgeSBT** | *(none)* | Soulbound ERC-721 badges |
| **MarketingVault** | `address(0)` (deferred TENX token) | Time-locked TENX token distribution |
| **RewardVoucher** | `"Prime10X Voucher"`, `"P10X-V"` | Soulbound ERC-721 reward vouchers |

> **RaffleVault** is not included in this deploy script. It takes a custom `owner_` address in its constructor, so it can be deployed separately with the team as the initial owner.

---

## Pre-Deploy Setup

### 1. CDP Credentials

Go to [portal.cdp.coinbase.com](https://portal.cdp.coinbase.com) and create:

- **API Key** — gives you a Key ID and Key Secret
- **Wallet Secret** — used by CDP to sign transactions server-side

### 2. Environment File

```bash
cp .env.example .env
```

Fill in your `.env`:

```
CDP_API_KEY_ID=<your-key-id>
CDP_API_KEY_SECRET=<your-key-secret>
CDP_WALLET_SECRET=<your-wallet-secret>
```

### 3. Install Dependencies

```bash
cd scripts && npm install && cd ..
```

---

## Deploy

```bash
# Build Solidity artifacts
forge build

# Deploy to Base Sepolia (default)
npx --prefix scripts tsx scripts/deploy-base-sepolia.ts

# Deploy to Base Mainnet (requires funded deployer)
npx --prefix scripts tsx scripts/deploy-base-sepolia.ts base
```

On Base Sepolia the script auto-funds the deployer from the faucet. On mainnet the deployer EOA must already have ETH.

After deploy, check `contract-addresses.md` for addresses and BaseScan links.

---

## Post-Deploy Configuration

Do these steps **before** transferring ownership to the team.

### Step 1 — Set the TENX token address on MarketingVault

```
MarketingVault.setTokenAddress(<TENX_TOKEN_ADDRESS>)
```

This is a **one-shot call** — it can never be changed once set.

### Step 2 — Set claim-enable dates

```
MarketingVault.setClaimEnableDate(<unix_timestamp>)
RewardVoucher.setClaimEnableDate(<unix_timestamp>)
```

These can be updated later by the owner (or by the emergency admin).

### Step 3 — (Optional) Set emergency admin

```
MarketingVault.setEmergencyAdmin(<multisig_or_admin_address>)
RewardVoucher.setEmergencyAdmin(<multisig_or_admin_address>)
```

The emergency admin can update claim-enable dates without going through the owner. Useful for a multisig safety net. This role is **separate from ownership** — transferring ownership does not move it.

### Step 4 — (Optional) Add distributors on MarketingVault

```
MarketingVault.setDistributor(<address>, true)
```

Distributors can allocate locked tokens on behalf of the owner. The new owner can manage this after transfer.

---

## Ownership Transfer

All three contracts use **Ownable2Step** (two-step transfer). This is the safest pattern — the new owner must explicitly accept.

### For each contract:

```
// Step 1: Current owner initiates transfer
contract.transferOwnership(<new_owner_address>)

// Step 2: New owner accepts (from their wallet)
contract.acceptOwnership()
```

Until `acceptOwnership()` is called, the original deployer remains the owner. There is no risk of accidentally sending ownership to a wrong address.

### What transfers with ownership

| | Transfers | Stays |
| --- | --- | --- |
| Owner role | Yes | |
| Emergency admin | | Must be re-set by new owner |
| Distributors | | Managed by new owner via `setDistributor()` |
| TENX token address | | Already locked (one-shot) |

### Warning: `renounceOwnership()`

None of the contracts disable `renounceOwnership()`. If called, ownership is permanently abandoned — **no one can ever admin the contract again**. The team should be warned never to call this.

---

## Contract-Specific Notes

### BadgeSBT

- Owner can `mintBadge()` and `revokeBadge()`
- Badges are soulbound (non-transferable)
- No additional privileged roles

### MarketingVault

- `setTokenAddress()` is irreversible (one-shot)
- Claims are blocked until `claimEnableDate` passes
- `rescueTokens()` can recover mistakenly sent tokens (with safeguards for TENX)

### RewardVoucher

- Owner can `mintVoucher()` and `revokeVoucher()`
- Vouchers are soulbound (non-transferable)
- Redeemed vouchers are permanently marked
- `setBaseURI()` controls metadata endpoint

### RaffleVault (not in this deploy)

- Takes `owner_` in constructor — can set team as owner directly
- `tenxToken` is immutable (set at deploy, never changeable)
- `setTGETimestamp()` is one-shot
- Lock period: TGE + 365 days (can be toggled via `setLockEnforced()`)
