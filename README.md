# Prime10X Smart Contracts

Solidity contracts for the Prime10X ecosystem, built with Foundry and deployed via Coinbase CDP SDK.

## Contracts

| Contract | Purpose |
| --- | --- |
| **Prime10XBadgeSBT** | Soulbound ERC-721 badges awarded for on-chain achievements |
| **Prime10XMarketingVault** | Time-locked TENX token distribution with season-based allocations |
| **Prime10XRewardVoucher** | Soulbound ERC-721 reward vouchers redeemable for TENX |
| **Prime10XRaffleVault** | Merkle-proof raffle rewards with TGE + 365-day lock |

## Base Sepolia Deployment

| Contract | Address | BaseScan |
| --- | --- | --- |
| BadgeSBT | `0x535dbdde4f792ac9b342ab08cb2c8ee42b22659b` | [contract](https://sepolia.basescan.org/address/0x535dbdde4f792ac9b342ab08cb2c8ee42b22659b) / [deploy tx](https://sepolia.basescan.org/tx/0x93b4bd7d1991bd227558bf0e75b871dc12e9ddb778cb2f6990171ed7b7612c2d) |
| MarketingVault | `0x8b981488296de50289ae26b67516333d8ba216ea` | [contract](https://sepolia.basescan.org/address/0x8b981488296de50289ae26b67516333d8ba216ea) / [deploy tx](https://sepolia.basescan.org/tx/0x83494f69a912c410b5b90d499f18a60882ebaca5f55545976179190025281727) |
| RewardVoucher | `0x0cea12c59fa4704ff153e2df1282e6c7a1529880` | [contract](https://sepolia.basescan.org/address/0x0cea12c59fa4704ff153e2df1282e6c7a1529880) / [deploy tx](https://sepolia.basescan.org/tx/0xe1d3c4f63c31878af03d1f0566dcd3eba1a8ad8791fa1a3bbd1c9cd6023a2017) |

Deployer: [`0x756F6DdCB76456D563B2d1A0c303E79B1170E5b1`](https://sepolia.basescan.org/address/0x756F6DdCB76456D563B2d1A0c303E79B1170E5b1)

> RaffleVault is deployed separately — it takes a custom `owner_` in its constructor.

> MarketingVault token address not yet set. Call `setTokenAddress()` after TENX deployment.

## Tech Stack

- **Solidity** 0.8.28 (Cancun EVM, optimizer 200 runs)
- **Foundry** for compilation and testing
- **OpenZeppelin** v5.5.0 (ERC-721, Ownable2Step, ReentrancyGuard, MerkleProof)
- **Coinbase CDP SDK** for managed-key deployment (no raw private keys)

## Project Structure

```
contracts/          Solidity source
test/               Foundry tests (106 tests)
scripts/            TypeScript deploy script (CDP SDK + viem)
out/                Foundry build artifacts (gitignored)
handoff.md          Ownership transfer guide
contract-addresses.md   Auto-generated deploy addresses
```

## Build and Test

```bash
forge build
forge test
```

## Deploy

### Prerequisites

1. Get CDP credentials from [portal.cdp.coinbase.com](https://portal.cdp.coinbase.com)
2. Create `.env` from the example:

```bash
cp .env.example .env
```

```
CDP_API_KEY_ID=<your-key-id>
CDP_API_KEY_SECRET=<your-key-secret>
CDP_WALLET_SECRET=<your-wallet-secret>
```

3. Install script dependencies:

```bash
cd scripts && npm install && cd ..
```

### Run

```bash
forge build

# Base Sepolia (default — auto-funds from faucet)
npx --prefix scripts tsx scripts/deploy-base-sepolia.ts

# Base Mainnet (deployer must already have ETH)
npx --prefix scripts tsx scripts/deploy-base-sepolia.ts base
```

Deployed addresses and BaseScan links are written to `contract-addresses.md`.

## Post-Deploy Configuration

These steps should be done **before** transferring ownership. See [handoff.md](handoff.md) for the full guide.

1. **Set TENX token address** on MarketingVault (`setTokenAddress()` — one-shot, irreversible)
2. **Set claim-enable dates** on MarketingVault and RewardVoucher
3. **Set emergency admin** (optional) on MarketingVault and RewardVoucher
4. **Add distributors** (optional) on MarketingVault

## Ownership Transfer

All contracts use **Ownable2Step** — a two-step transfer where the new owner must explicitly accept:

```
contract.transferOwnership(<new_owner>)   // current owner initiates
contract.acceptOwnership()                // new owner accepts
```

See [handoff.md](handoff.md) for what transfers with ownership, what stays, and important warnings.
