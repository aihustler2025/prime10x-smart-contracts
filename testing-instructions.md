# Prime10X — Base Sepolia Testing Instructions

These instructions walk through testing all three contracts using BaseScan's built-in read/write interface. No coding required.

---

## Before you start

You will need:
- MetaMask (or any browser wallet) connected to the **Base Sepolia** network
- A small amount of Sepolia ETH in your wallet for gas (free from a faucet — try https://www.alchemy.com/faucets/base-sepolia)
- Your wallet address: `0x57cb69D41aD0A413d718DcCd5f6551e4abE526e9`

**How to use BaseScan's write interface (applies to every step below):**
1. Open the contract link
2. Click the **Contract** tab
3. Click **Write Contract**
4. Click **Connect to Web3** and connect your wallet
5. Find the function by name, fill in the fields, and click **Write**
6. Approve the transaction in MetaMask

For read functions, use the **Read Contract** tab instead. No wallet or gas needed.

---

## Part 1 — Accept ownership on all three contracts

We transferred ownership to your wallet, but you need to confirm it on each contract. Do this first before anything else.

**Badge SBT**
https://sepolia.basescan.org/address/0x535dbdde4f792ac9b342ab08cb2c8ee42b22659b#writeContract

- Find `acceptOwnership`
- No fields to fill in, just click **Write**

**Marketing Vault**
https://sepolia.basescan.org/address/0x8b981488296de50289ae26b67516333d8ba216ea#writeContract

- Same — find `acceptOwnership`, click **Write**

**Reward Voucher**
https://sepolia.basescan.org/address/0x0cea12c59fa4704ff153e2df1282e6c7a1529880#writeContract

- Same — find `acceptOwnership`, click **Write**

**Check it worked:** On any contract, go to **Read Contract** and call `owner`. It should return your address: `0x57cb69D41aD0A413d718DcCd5f6551e4abE526e9`.

---

## Part 2 — Badge SBT

https://sepolia.basescan.org/address/0x535dbdde4f792ac9b342ab08cb2c8ee42b22659b

### 2a. Mint a badge

Go to **Write Contract**, find `mintBadge`, and enter:

| Field | Value |
|-------|-------|
| to | `0x57cb69D41aD0A413d718DcCd5f6551e4abE526e9` (your address) |
| season | `1` |
| badgeType | `0` |

Click **Write**. Expected: transaction succeeds.

### 2b. Confirm the badge exists

Go to **Read Contract**:

- `walletOf` — enter your address and season `1`. Should return `1` (the token ID).
- `totalSupply` — should return `1`.

### 2c. Confirm badges cannot be transferred (soulbound)

Go to **Write Contract**, find `transferFrom`, and enter:

| Field | Value |
|-------|-------|
| from | your address |
| to | any other address |
| tokenId | `1` |

Click **Write**. Expected: transaction **fails** with a "Soulbound" error. This is correct behaviour.

### 2d. Revoke the badge

Go to **Write Contract**, find `revokeBadge`, enter token ID `1`, and click **Write**.

Confirm with **Read Contract**:
- `totalSupply` should now return `0`
- `walletOf` for your address and season `1` should return `0`

---

## Part 3 — Reward Voucher

https://sepolia.basescan.org/address/0x0cea12c59fa4704ff153e2df1282e6c7a1529880

### 3a. Set the base URI

Go to **Write Contract**, find `setBaseURI`, and enter:

```
ipfs://bafybeigqbvjhfkwvsv7ra3ez7n5p7gz6irbqedbmwi7llckhsfgufz7mci
```

Click **Write**. This links the contract to the artwork on IPFS. The final metadata URI will be set again before mainnet launch.

### 3b. Mint a voucher

Find `mintVoucher` and enter:

| Field | Value |
|-------|-------|
| to | `0x57cb69D41aD0A413d718DcCd5f6551e4abE526e9` |
| tenxAmount | `75` |
| seasonId | `1` |

Click **Write**. Expected: transaction succeeds. This mints token ID `1`.

### 3c. Check the voucher details

Go to **Read Contract**:

- `getVoucherInfo` — enter token ID `1`. Should return: amount `75`, season `1`, redeemed `false`.
- `vouchersOf` — enter your address. Should return `[1]`.
- `tokenURI` — enter `1`. Should return an IPFS URI for the token.

### 3d. Enable redemptions (test only)

To test redemption, you need to set the claim date to a time in the past.

Go to **Write Contract**, find `setClaimEnableDate`, and enter:

```
1738368000
```

(This is February 1, 2026 — already in the past, so redemptions will be open immediately.)

Confirm with **Read Contract**: `isRedeemable` should return `true`.

### 3e. Redeem the voucher

Go to **Write Contract**, find `redeemVoucher`, enter token ID `1`, and click **Write**.

Expected: transaction succeeds. The voucher is burned.

### 3f. Confirm it cannot be redeemed twice

Try calling `redeemVoucher` with token ID `1` again. Expected: transaction **fails**. The token no longer exists.

### 3g. Test revoke (optional)

Mint a second voucher (same values as 3b — it will be token ID `2`). Then go to **Write Contract**, find `revokeVoucher`, enter `2`, and click **Write**.

Expected: transaction succeeds, voucher is burned.

---

## Part 4 — Marketing Vault

https://sepolia.basescan.org/address/0x8b981488296de50289ae26b67516333d8ba216ea

Note: full testing of token deposits and claims requires the TENX token to be deployed first. The steps below cover what can be tested now.

### 4a. Set the claim enable date

Go to **Write Contract**, find `setClaimEnableDate`, and enter `1738368000` (same past timestamp as above).

Confirm with **Read Contract**: `isClaimEnabled` should return `true`.

### 4b. Set an emergency admin

Find `setEmergencyAdmin` and enter your address. Click **Write**.

This confirms the emergency admin role works. In production, this will be a multi-sig wallet.

### 4c. Set a distributor

Find `setDistributor` and enter:

| Field | Value |
|-------|-------|
| account | your address |
| isDistributor | `true` |

Click **Write**. In production, distributor addresses are set before the batch allocation runs.

---

## Summary checklist

| Test | Expected result |
|------|----------------|
| acceptOwnership on all 3 contracts | `owner` returns your address |
| Mint badge | Succeeds |
| Badge transfer | Fails with Soulbound error |
| Revoke badge | Succeeds, supply drops to 0 |
| Set base URI | Succeeds |
| Mint voucher | Succeeds |
| tokenURI returns IPFS link | Confirmed in read |
| Redeem voucher after claim date | Succeeds |
| Redeem same voucher again | Fails |
| Revoke voucher | Succeeds |
| Marketing Vault claim date set | `isClaimEnabled` returns true |

Once you have reviewed and are happy with everything, please let Andrew know and he will proceed with the mainnet deployment plan.
