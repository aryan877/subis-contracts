import { Wallet, Provider, Contract } from "zksync-web3";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import * as dotenv from "dotenv";

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

  const planId = parseInt(process.env.PLAN_ID!, 10);
  try {
    // Get the plan details
    const plan = await subscriptionManager.plans(planId);
    console.log(plan);

    if (!plan.exists) {
      console.log(`Plan with ID ${planId} does not exist.`);
      return;
    }

    if (plan.isLive) {
      console.log(`Plan with ID ${planId} is already live.`);
      return;
    }

    // Make the plan live
    const tx = await subscriptionManager.makePlanLive(planId);
    await tx.wait();

    console.log(`Plan with ID ${planId} has been made live.`);
  } catch (error) {
    console.error(`Error making plan live: ${error}`);
  }
}
