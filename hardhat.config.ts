import { HardhatUserConfig } from "hardhat/config";
import "@matterlabs/hardhat-zksync-chai-matchers";
import "@matterlabs/hardhat-zksync-deploy";
import "@matterlabs/hardhat-zksync-solc";
import "@matterlabs/hardhat-zksync-verify";

import * as dotenv from "dotenv";
dotenv.config();

const zkSyncTestnet = {
  url: "https://sepolia.era.zksync.dev",
  ethNetwork: "sepolia", // Can also be the RPC URL of the network (e.g. `https://goerli.infura.io/v3/<API_KEY>`)
  zksync: true,
  verifyURL: "https://explorer.sepolia.era.zksync.dev/contract_verification",
};

const config: HardhatUserConfig = {
  zksolc: {
    version: "latest",
    settings: {
      isSystem: true,
    },
  },
  defaultNetwork: "zkSyncTestnet",
  networks: {
    hardhat: {
      zksync: true,
    },
    zkSyncTestnet,
  },
  solidity: {
    version: "0.8.17",
  },
};

export default config;
