# Prime10X — Base Sepolia Testing Instructions

These instructions walk through testing all three contracts using BaseScan. No coding required.

---

## How BaseScan read/write works

Each contract has a page on BaseScan. Here is how to navigate it:

1. Open a contract link (provided in each section below)
2. Click the **Contract** tab — it sits between "Transactions" and "Events" near the top of the page
3. Inside the Contract tab, you will see three sub-tabs: **Code**, **Read Contract**, and **Write Contract**

**Read Contract** — for checking data. Free, no wallet needed. Just fill in any fields and click **Query**.

**Write Contract** — for sending transactions. Costs a small amount of gas.
- Click **Connect to Web3** at the top of the Write Contract tab
- Connect your wallet when prompted
- Find the function by name, fill in the fields, and click **Write**
- Approve the transaction in your wallet

That's it. The steps below tell you exactly which tab and function to use each time.

---

## Part 1 — Accept ownership on all three contracts

Ownership of all three contracts has been transferred to your wallet, but you need to confirm it on each one. Do this before anything else — without it, none of the owner-only functions will work.

**Badge SBT**
https://sepolia.basescan.org/address/0x535dbdde4f792ac9b342ab08cb2c8ee42b22659b#writeContract

- Go to **Write Contract**, find `acceptOwnership`, and click **Write**. No fields to fill in.

**Marketing Vault**
https://sepolia.basescan.org/address/0x8b981488296de50289ae26b67516333d8ba216ea#writeContract

- Go to **Write Contract**, find `acceptOwnership`, and click **Write**.

**Reward Voucher**
https://sepolia.basescan.org/address/0x0cea12c59fa4704ff153e2df1282e6c7a1529880#writeContract

- Go to **Write Contract**, find `acceptOwnership`, and click **Write**.

**Confirm it worked:** On any of the three contracts, go to **Read Contract** and call `owner`. It should return your wallet address.

---

## Part 2 — Badge SBT

https://sepolia.basescan.org/address/0x535dbdde4f792ac9b342ab08cb2c8ee42b22659b

### 2a. Mint a badge

Go to **Write Contract**, find `mintBadge`, and enter:

| Field | Value |
|-------|-------|
| to | your wallet address |
| season | `1` |
| badgeType | `0` |

Click **Write**. Expected: transaction succeeds.

### 2b. Confirm the badge exists

Go to **Read Contract**:

- `walletOf` — enter your address and season `1`. Should return `1` (the token ID).
- `totalSupply` — should return `1`.

### 2c. Confirm badges cannot be transferred

Go to **Write Contract**, find `transferFrom`, and enter:

| Field | Value |
|-------|-------|
| from | your wallet address |
| to | any other address |
| tokenId | `1` |

Click **Write**. Expected: transaction **fails** with a "Soulbound" error. This is correct — badges are locked to the wallet they were minted to.

### 2d. Revoke the badge

Go to **Write Contract**, find `revokeBadge`, enter token ID `1`, and click **Write**.

Confirm with **Read Contract**:
- `totalSupply` should return `0`
- `walletOf` for your address and season `1` should return `0`

---

## Part 3 — Reward Voucher

https://sepolia.basescan.org/address/0x0cea12c59fa4704ff153e2df1282e6c7a1529880

### 3a. Set the base URI

Go to **Write Contract**, find `setBaseURI`, and enter:

```
ipfs://bafybeigqbvjhfkwvsv7ra3ez7n5p7gz6irbqedbmwi7llckhsfgufz7mci
```

Click **Write**. This points the contract at the artwork on IPFS. The final metadata URI will be updated before mainnet launch.

### 3b. Mint a voucher

Go to **Write Contract**, find `mintVoucher`, and enter:

| Field | Value |
|-------|-------|
| to | your wallet address |
| tenxAmount | `75` |
| seasonId | `1` |

Click **Write**. Expected: transaction succeeds. This creates token ID `1`.

### 3c. Check the voucher details

Go to **Read Contract**:

- `getVoucherInfo` — enter token ID `1`. Should return: amount `75`, season `1`, redeemed `false`.
- `vouchersOf` — enter your address. Should return `[1]`.
- `tokenURI` — enter `1`. Should return an IPFS link for the token.

### 3d. Enable redemptions

To test redeeming a voucher, you need to set the claim date to a point in the past. This unlocks redemptions immediately.

Go to **Write Contract**, find `setClaimEnableDate`, and enter:

```
1738368000
```

Go to **Read Contract** and call `isRedeemable`. It should return `true`.

### 3e. Redeem the voucher

Go to **Write Contract**, find `redeemVoucher`, enter token ID `1`, and click **Write**.

Expected: transaction succeeds. The voucher is burned.

### 3f. Confirm it cannot be redeemed twice

Try `redeemVoucher` with token ID `1` again. Expected: transaction **fails** — the token no longer exists.

### 3g. Test revoke (optional)

Mint a second voucher using the same values as step 3b — it will be assigned token ID `2`. Then go to **Write Contract**, find `revokeVoucher`, enter `2`, and click **Write**.

Expected: transaction succeeds, voucher is burned.

---

## Part 4 — Marketing Vault

https://sepolia.basescan.org/address/0x8b981488296de50289ae26b67516333d8ba216ea

Full deposit and claim testing requires the TENX token to be deployed first. The steps below cover everything that can be tested right now.

### 4a. Set the claim enable date

Go to **Write Contract**, find `setClaimEnableDate`, and enter `1738368000`.

Go to **Read Contract** and call `isClaimEnabled`. Should return `true`.

### 4b. Set an emergency admin

Go to **Write Contract**, find `setEmergencyAdmin`, enter your wallet address, and click **Write**.

In production this will be a multi-sig wallet, but this confirms the function works correctly.

### 4c. Set a distributor

Go to **Write Contract**, find `setDistributor`, and enter:

| Field | Value |
|-------|-------|
| account | your wallet address |
| isDistributor | `true` |

Click **Write**. Distributors are the addresses allowed to allocate tokens to users before the claim window opens.

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
| Redeem voucher after claim date set | Succeeds |
| Redeem same voucher again | Fails |
| Revoke voucher | Succeeds |
| Marketing Vault claim date set | `isClaimEnabled` returns true |

Once you are happy with everything, let me know and I will move forward with the mainnet deployment plan.
