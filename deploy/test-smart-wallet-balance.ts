import { Wallet, Provider } from "zksync-web3";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import * as dotenv from "dotenv";
import { ethers } from "ethers";

export default async function (hre: HardhatRuntimeEnvironment) {
  dotenv.config();

  // @ts-ignore target zkSyncTestnet in config file which can be testnet or local
  const provider = new Provider(hre.config.networks.zkSyncTestnet.url);
  const subscriptionAccountAddress = process.env.SUBSCRIPTION_ACCOUNT_ADDRESS!;

  // Get the balance of the subscription account
  const balanceWei = await provider.getBalance(subscriptionAccountAddress);

  // Convert the balance from Wei to Ether
  const balanceEther = ethers.utils.formatEther(balanceWei);

  console.log(`Balance of the smart contract account: ${balanceEther} ETH`);
}
