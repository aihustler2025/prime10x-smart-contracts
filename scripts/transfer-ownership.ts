import { CdpClient } from "@coinbase/cdp-sdk";
import {
  createPublicClient,
  encodeFunctionData,
  http,
  keccak256,
  serializeTransaction,
  type Chain,
  type Hex,
  type TransactionSerializableEIP1559,
} from "viem";
import { base, baseSepolia } from "viem/chains";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import dotenv from "dotenv";

const __dirname = dirname(fileURLToPath(import.meta.url));

dotenv.config({ path: resolve(__dirname, "../.env") });

// ── Network config ───────────────────────────────────────────────────────────

const NETWORKS = {
  "base-sepolia": {
    chain: baseSepolia,
    explorer: "https://sepolia.basescan.org",
    label: "Base Sepolia",
  },
  "base": {
    chain: base,
    explorer: "https://basescan.org",
    label: "Base Mainnet",
  },
} as const;

type NetworkId = keyof typeof NETWORKS;

const networkArg = process.argv[2] as NetworkId | undefined;
const NETWORK: NetworkId = networkArg && networkArg in NETWORKS ? networkArg : "base-sepolia";
const NET = NETWORKS[NETWORK];

// ── Contract addresses per network ──────────────────────────────────────────

const CONTRACT_ADDRESSES: Record<NetworkId, Record<string, Hex>> = {
  "base-sepolia": {
    BadgeSBT:       "0x535dbdde4f792ac9b342ab08cb2c8ee42b22659b",
    MarketingVault: "0x8b981488296de50289ae26b67516333d8ba216ea",
    RewardVoucher:  "0x0cea12c59fa4704ff153e2df1282e6c7a1529880",
  },
  "base": {
    // Populate when mainnet is deployed
    BadgeSBT:       "0x0000000000000000000000000000000000000000",
    MarketingVault: "0x0000000000000000000000000000000000000000",
    RewardVoucher:  "0x0000000000000000000000000000000000000000",
  },
};

// ── ABI fragments ────────────────────────────────────────────────────────────

const TRANSFER_OWNERSHIP_ABI = [
  {
    name: "transferOwnership",
    type: "function",
    inputs: [{ name: "newOwner", type: "address" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
] as const;

// ── Send a contract call transaction ────────────────────────────────────────

async function sendCall(
  cdpAccount: { address: string; sign: (p: { hash: Hex }) => Promise<Hex> },
  publicClient: ReturnType<typeof createPublicClient>,
  nonce: number,
  to: Hex,
  data: Hex,
): Promise<string> {
  const feeData = await publicClient.estimateFeesPerGas();

  const gasEstimate = await publicClient.estimateGas({
    account: cdpAccount.address as Hex,
    to,
    data,
  });

  const unsignedTx: TransactionSerializableEIP1559 = {
    type: "eip1559",
    chainId: NET.chain.id,
    nonce,
    maxFeePerGas: feeData.maxFeePerGas!,
    maxPriorityFeePerGas: feeData.maxPriorityFeePerGas!,
    gas: gasEstimate,
    to,
    data,
    value: 0n,
  };

  const serializedUnsigned = serializeTransaction(unsignedTx);
  const txHash = keccak256(serializedUnsigned);
  const signature = await cdpAccount.sign({ hash: txHash });

  const r = `0x${signature.slice(2, 66)}` as Hex;
  const s = `0x${signature.slice(66, 130)}` as Hex;
  const v = parseInt(signature.slice(130, 132), 16);
  const yParity = v >= 27 ? v - 27 : v;

  const signedTx = serializeTransaction(unsignedTx, {
    r,
    s,
    yParity: yParity as 0 | 1,
  });

  const broadcastHash = await publicClient.sendRawTransaction({
    serializedTransaction: signedTx,
  });

  await publicClient.waitForTransactionReceipt({ hash: broadcastHash });
  return broadcastHash;
}

// ── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  const NEW_OWNER = "0x57cb69D41aD0A413d718DcCd5f6551e4abE526e9" as Hex;
  const contracts = CONTRACT_ADDRESSES[NETWORK];

  console.log(`Prime10X — Transfer Ownership (${NET.label})\n`);
  console.log(`New owner (pending): ${NEW_OWNER}`);
  console.log(`Network:             ${NET.label}\n`);

  // Sanity-check: skip if any address is zero (mainnet not yet deployed)
  for (const [name, addr] of Object.entries(contracts)) {
    if (addr === "0x0000000000000000000000000000000000000000") {
      console.error(`ERROR: ${name} address not set for ${NET.label}. Update CONTRACT_ADDRESSES.`);
      process.exit(1);
    }
  }

  const cdp = new CdpClient();
  const account = await cdp.evm.getOrCreateAccount({ name: "prime10x-deployer" });
  console.log(`Deployer (current owner): ${account.address}`);
  console.log(`  ${NET.explorer}/address/${account.address}\n`);

  const publicClient = createPublicClient({
    chain: NET.chain as Chain,
    transport: http(),
  });

  let nonce = await publicClient.getTransactionCount({
    address: account.address as Hex,
  });

  for (const [name, contractAddress] of Object.entries(contracts)) {
    console.log(`Initiating ownership transfer for ${name} (${contractAddress})...`);

    const data = encodeFunctionData({
      abi: TRANSFER_OWNERSHIP_ABI,
      functionName: "transferOwnership",
      args: [NEW_OWNER],
    });

    const txHash = await sendCall(account, publicClient, nonce++, contractAddress as Hex, data);
    console.log(`  ✓ transferOwnership sent: ${NET.explorer}/tx/${txHash}\n`);
  }

  console.log("─────────────────────────────────────────────────────────────");
  console.log("NEXT STEP — new owner must accept on each contract.");
  console.log(`Call acceptOwnership() from ${NEW_OWNER} on:`);
  for (const [name, addr] of Object.entries(contracts)) {
    console.log(`  ${name}: ${NET.explorer}/address/${addr}#writeContract`);
  }
  console.log("─────────────────────────────────────────────────────────────");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
