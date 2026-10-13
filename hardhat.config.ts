
import { defineConfig } from "hardhat/config";

export default defineConfig({
  paths: {
    sources: "./blockchain/contracts",
  },
  solidity: {
    version: "0.8.34",
  },
});
