
import { ethers } from "ethers";
import { readFile } from "node:fs/promises";

const RPC_URL = "http://127.0.0.1:8545";

// Local Hardhat Account #0 — development only.



const PRIVATE_KEY =
  "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";




const ARTIFACT_PATH =
  "./artifacts/blockchain/contracts/Pharmatrace.sol/PharmaTrace.json";

async function main() {
  const artifact = JSON.parse(
    await readFile(ARTIFACT_PATH, "utf8")
  );

  if (!artifact.abi || !artifact.bytecode) {
    throw new Error("Contract ABI or bytecode is missing. Compile first.");
  }

  const provider = new ethers.JsonRpcProvider(RPC_URL);

  try {
    const network = await provider.getNetwork();
    console.log("Connected to local blockchain.");
    console.log("Chain ID:", network.chainId.toString());

    const wallet = new ethers.Wallet(PRIVATE_KEY, provider);

    console.log("Deploying PharmaTrace from:", wallet.address);

    const factory = new ethers.ContractFactory(
      artifact.abi,
      artifact.bytecode,
      wallet
    );

    const contract = await factory.deploy();
    console.log("Deployment transaction:", contract.deploymentTransaction().hash);

    await contract.waitForDeployment();

    const address = await contract.getAddress();

    console.log("\nPharmaTrace deployed successfully!");
    console.log("Contract address:", address);
    console.log("Admin account:", wallet.address);
  } finally {
    await provider.destroy();
  }
}

main().catch((error) => {
  console.error("Deployment failed:", error.shortMessage || error.message);
  process.exitCode = 1;
});
