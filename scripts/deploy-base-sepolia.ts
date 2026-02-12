import { CdpClient } from "@coinbase/cdp-sdk";
import { createPublicClient, encodeDeployData, http, type Abi, type Chain } from "viem";
import { base, baseSepolia } from "viem/chains";
import { readFileSync, writeFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import dotenv from "dotenv";

const __dirname = dirname(fileURLToPath(import.meta.url));

// Load .env from project root
dotenv.config({ path: resolve(__dirname, "../.env") });

// ── Network config ──────────────────────────────────────────────────────────

const NETWORKS = {
  "base-sepolia": {
    chain: baseSepolia,
    explorer: "https://sepolia.basescan.org",
    label: "Base Sepolia",
    faucet: true,
  },
  "base": {
    chain: base,
    explorer: "https://basescan.org",
    label: "Base Mainnet",
    faucet: false,
  },
} as const;

type NetworkId = keyof typeof NETWORKS;

const networkArg = process.argv[2] as NetworkId | undefined;
const NETWORK: NetworkId = networkArg && networkArg in NETWORKS ? networkArg : "base-sepolia";
const NET = NETWORKS[NETWORK];

// ── Helpers ─────────────────────────────────────────────────────────────────

interface FoundryArtifact {
  abi: Abi;
  bytecode: { object: string };
}

function readArtifact(contractName: string): FoundryArtifact {
  const artifactPath = resolve(
    __dirname,
    `../out/${contractName}.sol/${contractName}.json`,
  );
  return JSON.parse(readFileSync(artifactPath, "utf-8"));
}

const publicClient = createPublicClient({
  chain: NET.chain as Chain,
  transport: http(),
});

// ── Deploy a single contract ────────────────────────────────────────────────

async function deployContract(
  cdp: CdpClient,
  deployer: string,
  contractName: string,
  constructorArgs: unknown[] = [],
): Promise<{ address: string; txHash: string }> {
  const artifact = readArtifact(contractName);

  const data = constructorArgs.length > 0
    ? encodeDeployData({
        abi: artifact.abi,
        bytecode: artifact.bytecode.object as `0x${string}`,
        args: constructorArgs,
      })
    : artifact.bytecode.object as `0x${string}`;

  console.log(`  Deploying ${contractName}...`);

  const { transactionHash } = await cdp.evm.sendTransaction({
    address: deployer as `0x${string}`,
    network: NETWORK,
    transaction: { data },
  });

  console.log(`  Tx: ${NET.explorer}/tx/${transactionHash}`);

  const receipt = await publicClient.waitForTransactionReceipt({
    hash: transactionHash as `0x${string}`,
  });

  if (!receipt.contractAddress) {
    throw new Error(`${contractName} deployment failed — no contract address in receipt`);
  }

  console.log(`  Contract: ${NET.explorer}/address/${receipt.contractAddress}`);
  console.log(`  Deployed at: ${receipt.contractAddress}\n`);
  return { address: receipt.contractAddress, txHash: transactionHash };
}

// ── Main ────────────────────────────────────────────────────────────────────

async function main() {
  console.log(`Prime10X — ${NET.label} Deploy\n`);

  // 1. Init CDP client (reads CDP_API_KEY_ID, CDP_API_KEY_SECRET, CDP_WALLET_SECRET from env)
  const cdp = new CdpClient();

  // 2. Get or create a named deployer account
  const account = await cdp.evm.getOrCreateAccount({ name: "prime10x-deployer" });
  console.log(`Deployer: ${account.address}`);
  console.log(`  ${NET.explorer}/address/${account.address}\n`);

  // 3. Fund from faucet (testnet only)
  if (NET.faucet) {
    console.log("Requesting faucet funds...");
    const faucet = await cdp.evm.requestFaucet({
      address: account.address,
      network: NETWORK as "base-sepolia",
      token: "eth",
    });
    console.log(`Faucet tx: ${NET.explorer}/tx/${faucet.transactionHash}\n`);

    await publicClient.waitForTransactionReceipt({
      hash: faucet.transactionHash as `0x${string}`,
    });
  }

  // 4. Deploy contracts
  const deployed: Record<string, { address: string; txHash: string }> = {};

  deployed.BadgeSBT = await deployContract(
    cdp, account.address,
    "Prime10XBadgeSBT",
  );

  deployed.MarketingVault = await deployContract(
    cdp, account.address,
    "Prime10XMarketingVault",
    ["0x0000000000000000000000000000000000000000"], // deferred TENX token
  );

  deployed.RewardVoucher = await deployContract(
    cdp, account.address,
    "Prime10XRewardVoucher",
    ["Prime10X Voucher", "P10X-V"],
  );

  // 5. Write contract-addresses.md
  const md = [
    "# Prime10X Contract Addresses",
    "",
    `## ${NET.label}`,
    "",
    "| Contract | Address | BaseScan |",
    "| --- | --- | --- |",
    ...Object.entries(deployed).map(
      ([name, { address, txHash }]) =>
        `| ${name} | \`${address}\` | [contract](${NET.explorer}/address/${address}) / [deploy tx](${NET.explorer}/tx/${txHash}) |`,
    ),
    "",
    `Deployer: [\`${account.address}\`](${NET.explorer}/address/${account.address})`,
    "",
    "MarketingVault token address not yet set. Call `setTokenAddress()` after TENX deployment.",
    "",
  ].join("\n");

  const mdPath = resolve(__dirname, "../contract-addresses.md");
  writeFileSync(mdPath, md);
  console.log("Addresses written to contract-addresses.md");

  console.log("\nDone!");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
