import { ethers } from "ethers";
import { readFile } from "node:fs/promises";

const RPC_URL = "http://127.0.0.1:8545";
const PRIVATE_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
const CONTRACT_ADDRESS = "0x5FbDB2315678afecb367f032d93F642f64180aa3";
const ARTIFACT_PATH = "./artifacts/blockchain/contracts/Pharmatrace.sol/PharmaTrace.json";

async function main() {
  const artifact = JSON.parse(await readFile(ARTIFACT_PATH, "utf8"));
  const provider = new ethers.JsonRpcProvider(RPC_URL);

  try {
    const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
    const contract = new ethers.Contract(CONTRACT_ADDRESS, artifact.abi, wallet);
    const id = "PT-TEST-002";
    const expiry = Math.floor(Date.now() / 1000) + 365 * 24 * 60 * 60;

    const tx = await contract.registerMedicine(
      id, "PharmaTrace Demo Medicine", "BATCH-DEMO-001",
      expiry, "QmRPfUZb5v52nNjgV6wWE7biJnaHJbY9voczuVT25qujvr"
    );

    console.log("Registration transaction:", tx.hash);
    await tx.wait();

    const record = await contract.getMedicine(id);
    console.log("Medicine registered successfully!");
    console.log("ID:", record.id);
    console.log("Name:", record.name);
    console.log("Batch:", record.batch);
    console.log("Exists:", record.exists);
  } finally {
    await provider.destroy();
  }
}

main().catch(error => {
  console.error("Registration failed:", error.shortMessage || error.message);
  process.exitCode = 1;
});




