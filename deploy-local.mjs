import { ethers } from "ethers";
import { readFile } from "node:fs/promises";

const RPC_URL = "http://127.0.0.1:8545";
const PRIVATE_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
const ARTIFACT_PATH = "./artifacts/blockchain/contracts/Pharmatrace.sol/PharmaTrace.json";

const artifact = JSON.parse(await readFile(ARTIFACT_PATH, "utf8"));
const provider = new ethers.JsonRpcProvider(RPC_URL);

try {
  const network = await provider.getNetwork();
  if (network.chainId !== 31337n) {
    throw new Error(`Unexpected chain ID: ${network.chainId}`);
  }

  const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
  const factory = new ethers.ContractFactory(
    artifact.abi,
    artifact.bytecode,
    wallet
  );

  console.log("Deploying PharmaTrace to local Hardhat...");
  const contract = await factory.deploy();
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log("Deployment successful!");
  console.log("Contract address:", address);
  console.log("Admin/manufacturer:", wallet.address);
  console.log("Transaction:", contract.deploymentTransaction().hash);
} finally {
  await provider.destroy();
}
