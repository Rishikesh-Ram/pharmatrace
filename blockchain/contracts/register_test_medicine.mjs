import { ethers } from "ethers";
import { readFile } from "node:fs/promises";

const RPC_URL = "http://127.0.0.1:8545";
const ADMIN_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
const MFR_KEY = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d";
const CONTRACT_ADDRESS = "0x5FbDB2315678afecb367f032d93F642f64180aa3";
const ARTIFACT_PATH = "./artifacts/blockchain/contracts/Pharmatrace.sol/PharmaTrace.json";

async function main() {
  const artifact = JSON.parse(await readFile(ARTIFACT_PATH, "utf8"));
  const provider = new ethers.JsonRpcProvider(RPC_URL);

  try {
    const adminWallet = new ethers.Wallet(ADMIN_KEY, provider);
    const mfrWallet = new ethers.Wallet(MFR_KEY, provider);

    const contractAsAdmin = new ethers.Contract(CONTRACT_ADDRESS, artifact.abi, adminWallet);
    const contractAsMfr = new ethers.Contract(CONTRACT_ADDRESS, artifact.abi, mfrWallet);

    const mfrUser = await contractAsAdmin.users(mfrWallet.address);
    if (Number(mfrUser.role) !== 2 || Number(mfrUser.status) !== 1) {
      if (Number(mfrUser.role) === 0) {
        console.log("Registering manufacturer account...");
        const regTx = await contractAsMfr.register(
          2,
          "Demo Pharma Manufacturer",
          ethers.ZeroAddress,
          ethers.ZeroAddress
        );
        await regTx.wait();
      }
      console.log("Admin approving manufacturer account...");
      const appTx = await contractAsAdmin.approve(mfrWallet.address);
      await appTx.wait();
    }

    const medicineId = "PT-TEST-001";
    const expiry = Math.floor(Date.now() / 1000) + 365 * 24 * 60 * 60;

    const tx = await contractAsMfr.registerMedicine(
      medicineId,
      "PharmaTrace Demo Medicine",
      "BATCH-DEMO-001",
      expiry,
      "demo-image-reference",
      100
    );

    console.log("Registration transaction:", tx.hash);
    await tx.wait();

    const record = await contractAsMfr.getMedicine(medicineId);
    console.log("Medicine registered successfully!");
    console.log("ID:", record.id);
    console.log("Name:", record.name);
    console.log("Batch:", record.batch);
    console.log("Quantity:", record.quantity.toString());
    console.log("Exists:", record.exists);
  } finally {
    await provider.destroy();
  }
}

main().catch((error) => {
  console.error("Registration failed:", error.shortMessage || error.message);
  process.exitCode = 1;
});
