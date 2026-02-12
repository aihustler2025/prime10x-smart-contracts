import { CdpClient } from "@coinbase/cdp-sdk";
import {
  createPublicClient,
  encodeDeployData,
  http,
  keccak256,
  serializeTransaction,
  type Abi,
  type Chain,
  type Hex,
  type TransactionSerializableEIP1559,
} from "viem";
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

// ── Deploy a single contract ────────────────────────────────────────────────
//
// CDP's sendTransaction AND signTransaction APIs both reject contract-creation
// transactions (they require a `to` field). We work around this by:
//   1. Building the unsigned EIP-1559 tx ourselves
//   2. Signing its hash via account.sign() (calls signEvmHash — just signs
//      an arbitrary 32-byte hash, no tx parsing)
//   3. Assembling the signed tx and broadcasting via eth_sendRawTransaction

async function deployContract(
  cdpAccount: { address: string; sign: (p: { hash: Hex }) => Promise<Hex> },
  publicClient: ReturnType<typeof createPublicClient>,
  nonce: number,
  contractName: string,
  constructorArgs: unknown[] = [],
): Promise<{ address: string; txHash: string }> {
  const artifact = readArtifact(contractName);

  const deployData = constructorArgs.length > 0
    ? encodeDeployData({
        abi: artifact.abi,
        bytecode: artifact.bytecode.object as `0x${string}`,
        args: constructorArgs,
      })
    : artifact.bytecode.object as `0x${string}`;

  console.log(`  Deploying ${contractName} (nonce ${nonce})...`);

  // Get fee data from the network
  const feeData = await publicClient.estimateFeesPerGas();

  const gasEstimate = await publicClient.estimateGas({
    account: cdpAccount.address as `0x${string}`,
    data: deployData,
  });

  // Build unsigned EIP-1559 transaction (no `to` = contract creation)
  const unsignedTx: TransactionSerializableEIP1559 = {
    type: "eip1559",
    chainId: NET.chain.id,
    nonce,
    maxFeePerGas: feeData.maxFeePerGas!,
    maxPriorityFeePerGas: feeData.maxPriorityFeePerGas!,
    gas: gasEstimate,
    data: deployData,
    value: 0n,
  };

  // Serialize, hash, sign via CDP's signEvmHash (no tx parsing)
  const serializedUnsigned = serializeTransaction(unsignedTx);
  const txHash = keccak256(serializedUnsigned);
  const signature = await cdpAccount.sign({ hash: txHash });

  // Parse r, s, yParity from the 65-byte signature
  const r = `0x${signature.slice(2, 66)}` as Hex;
  const s = `0x${signature.slice(66, 130)}` as Hex;
  const v = parseInt(signature.slice(130, 132), 16);
  const yParity = v >= 27 ? v - 27 : v;

  // Re-serialize with signature and broadcast
  const signedTx = serializeTransaction(unsignedTx, {
    r,
    s,
    yParity: yParity as 0 | 1,
  });

  const broadcastHash = await publicClient.sendRawTransaction({
    serializedTransaction: signedTx,
  });

  console.log(`  Tx: ${NET.explorer}/tx/${broadcastHash}`);

  const receipt = await publicClient.waitForTransactionReceipt({
    hash: broadcastHash,
  });

  if (!receipt.contractAddress) {
    throw new Error(`${contractName} deployment failed — no contract address in receipt`);
  }

  console.log(`  Contract: ${NET.explorer}/address/${receipt.contractAddress}`);
  console.log(`  Deployed at: ${receipt.contractAddress}\n`);
  return { address: receipt.contractAddress, txHash: broadcastHash };
}

// ── Main ────────────────────────────────────────────────────────────────────

async function main() {
  console.log(`Prime10X — ${NET.label} Deploy\n`);

  // 1. Init CDP client
  const cdp = new CdpClient();

  // 2. Get or create a named deployer account
  const account = await cdp.evm.getOrCreateAccount({ name: "prime10x-deployer" });
  console.log(`Deployer: ${account.address}`);
  console.log(`  ${NET.explorer}/address/${account.address}\n`);

  // 3. Public client for RPC calls
  const publicClient = createPublicClient({
    chain: NET.chain as Chain,
    transport: http(),
  });

  // 4. Fund from faucet (testnet only)
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

  // 5. Deploy contracts — track nonce ourselves to avoid stale RPC reads
  let nonce = await publicClient.getTransactionCount({
    address: account.address as `0x${string}`,
  });

  const deployed: Record<string, { address: string; txHash: string }> = {};

  deployed.BadgeSBT = await deployContract(
    account, publicClient, nonce++,
    "Prime10XBadgeSBT",
  );

  deployed.MarketingVault = await deployContract(
    account, publicClient, nonce++,
    "Prime10XMarketingVault",
    ["0x0000000000000000000000000000000000000000"], // deferred TENX token
  );

  deployed.RewardVoucher = await deployContract(
    account, publicClient, nonce++,
    "Prime10XRewardVoucher",
    ["Prime10X Voucher", "P10X-V"],
  );

  // 6. Write contract-addresses.md
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
