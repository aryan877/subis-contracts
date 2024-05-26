import { Wallet, Provider, Contract } from "zksync-web3";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import * as dotenv from "dotenv";
import { ethers } from "ethers";

export default async function (hre: HardhatRuntimeEnvironment) {
  dotenv.config();

  // @ts-ignore target zkSyncTestnet in config file which can be testnet or local
  const provider = new Provider(hre.config.networks.zkSyncTestnet.url);
  const owner = new Wallet(process.env.WALLET_PRIVATE_KEY!, provider);
  const subscriptionManagerAddress = process.env.SUBSCRIPTION_MANAGER_ADDRESS!;

  const subscriptionManagerArtifact = await hre.artifacts.readArtifact(
    "SubscriptionManager"
  );
  const subscriptionManager = new Contract(
    subscriptionManagerAddress,
    subscriptionManagerArtifact.abi,
    owner
  );

  // Get the total number of plans
  const planCount = await subscriptionManager.planCount();
  console.log(`Total number of plans: ${planCount.toString()}`);

  for (let i = 0; i < planCount; i++) {
    const plan = await subscriptionManager.plans(i);
    const feeUSD = ethers.utils.formatUnits(plan.feeUSD, 8); // Format fee to USD with 8 decimal places

    console.log(`Plan ID: ${i}`);
    console.log(`  Name: ${plan.name}`);
    console.log(`  Fee USD: $${feeUSD}`);
    console.log(`  Exists: ${plan.exists}`);
    console.log("");
  }
}
