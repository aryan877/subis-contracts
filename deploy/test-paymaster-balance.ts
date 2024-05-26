import { Provider, Wallet } from "zksync-web3";
import * as ethers from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import dotenv from "dotenv";

dotenv.config();

async function readPaymasterBalance(hre: HardhatRuntimeEnvironment) {
  // @ts-ignore target zkSyncTestnet in config file which can be testnet or local
  const provider = new Provider(hre.config.networks.zkSyncTestnet.url);
  const wallet = new Wallet(process.env.WALLET_PRIVATE_KEY!, provider);

  const paymasterAddress = process.env.PAYMASTER_ADDRESS!;
  if (!paymasterAddress) {
    throw new Error("Paymaster address not provided in the .env file");
  }

  // Get the balance of the paymaster
  const paymasterBalance = await provider.getBalance(paymasterAddress);

  // Convert the balance from wei to ether
  const balanceInEther = ethers.utils.formatEther(paymasterBalance);
  console.log(`Paymaster ETH balance: ${balanceInEther} ETH`);
}

export default async function (hre: HardhatRuntimeEnvironment) {
  try {
    await readPaymasterBalance(hre);
  } catch (error) {
    console.error("Error reading paymaster balance:", error);
    process.exit(1);
  }
}
