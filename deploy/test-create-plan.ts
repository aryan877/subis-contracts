import { Wallet, Provider, Contract } from "zksync-web3";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import * as dotenv from "dotenv";
import * as fs from "fs";
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

  const planName = "Basic Plan";
  const feeUSD = ethers.utils.parseUnits("10", 8); // $10 fee (with 8 decimal places)

  const tx = await subscriptionManager.createPlan(planName, feeUSD);
  await tx.wait();

  const planId = await subscriptionManager.planCount();

  // Store the new plan ID in the .env file
  const envConfig = dotenv.parse(fs.readFileSync(".env"));
  envConfig.PLAN_ID = planId.toString();
  fs.writeFileSync(
    ".env",
    Object.entries(envConfig)
      .map(([key, val]) => `${key}=${val}`)
      .join("\n")
  );

  console.log(`Subscription plan created with ID: ${planId}`);
}
