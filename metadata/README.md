# Prime10X Season 1 — NFT Metadata & Pinata Upload Guide

## Folder structure

```
metadata/
  images/       ← Upload 1: drop Ross's 6 PNGs here, then upload this folder to Pinata
  tokens/
    1/          ← Upload 2: individual token JSONs go here (1.json, 2.json, …), then upload tokens/ to Pinata
  templates/    ← Tier templates (reference only — NOT uploaded to Pinata)
```

---

## Step 1 — Upload images to Pinata ✓ DONE

Images CID: `bafybeigqbvjhfkwvsv7ra3ez7n5p7gz6irbqedbmwi7llckhsfgufz7mci`

All 6 templates already have the real image URIs. If you need to re-upload:
1. Drop the 6 PNG files from Ross into `metadata/images/`:
   - `bronze.png`, `copper.png`, `silver.png`, `gold.png`, `diamond.png`, `prism.png`
2. In Pinata, click **Upload → Folder** and select the `metadata/images/` folder.

---

## Step 2 — Generate individual token JSON files (Apr 23 – May 6)

For each voucher you're minting, create a file `metadata/tokens/1/{tokenId}.json`.

**Token IDs are sequential starting at 1** — the first mint is `1.json`, second is `2.json`, etc.

### Fixed-tier tokens (Bronze / Copper / Silver / Gold / Diamond)

Copy the matching template from `metadata/templates/` and replace `<IMAGES_CID>`:

```bash
# Example: token 1 is a Bronze voucher
cp metadata/templates/bronze.json metadata/tokens/1/1.json
# Then open the file and replace <IMAGES_CID> with the real CID from Step 1
```

### Prism tokens (variable TENX per deal)

Copy `metadata/templates/prism.json`, replace `<IMAGES_CID>`, and also update:
- `"TENX Amount"` value → the negotiated amount from `creator_deals.tenx_amount`
- `"description"` → optionally mention the actual amount

```json
{ "trait_type": "TENX Amount", "value": 5000, "display_type": "number" }
```

---

## Step 3 — Upload token metadata to Pinata

Once all `metadata/tokens/1/*.json` files are generated:

1. In Pinata, click **Upload → Folder** and select the `metadata/tokens/` folder.
   - The folder must contain the `1/` subfolder (so Pinata's CID covers the season directory).
2. Note the resulting CID — this is `<METADATA_CID>`.

---

## Step 4 — Set the base URI on-chain

Call `setBaseURI` on the `Prime10XRewardVoucher` contract:

```
ipfs://<METADATA_CID>
```

The contract automatically appends `/{seasonId}/{tokenId}.json`, so token 42 (season 1) resolves to:

```
ipfs://<METADATA_CID>/1/42.json
```

Do this **before** batch minting so every token has metadata from the moment it's minted.

---

## Step 5 — Batch mint

Call `mintVoucher(walletAddress, tenxAmount, seasonId)` for each winner.
Token IDs are assigned sequentially by the contract — they must match the filenames you prepared.

> **Tip:** Do a dry run on Base Sepolia first to confirm all tokenURIs resolve correctly before minting on mainnet.

---

## TENX amounts per tier

| Tier    | TENX Amount |
|---------|-------------|
| Bronze  | 75          |
| Copper  | 125         |
| Silver  | 300         |
| Gold    | 1,000       |
| Diamond | 2,000       |
| Prism   | Per deal    |

---

## Key dates

| Date | Event |
|------|-------|
| Feb 23, 2026 | Season 1 starts |
| Apr 23, 2026 | Season 1 ends — start batch minting window |
| May 6, 2026  | Batch minting window closes |
| May 7, 2026  | TGE — `setClaimEnableDate` / `acceptOwnership` / redeem button goes live |
| May 7, 2027  | 12-month lock expires |
