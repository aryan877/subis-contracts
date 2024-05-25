import { utils, Wallet, Provider } from "zksync-web3";
import * as ethers from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import * as dotenv from "dotenv";
import * as fs from "fs";

export default async function (hre: HardhatRuntimeEnvironment) {
  dotenv.config();
  // @ts-ignore target zkSyncTestnet in config file which can be testnet or local
  const provider = new Provider(hre.config.networks.zkSyncTestnet.url);
  const wallet = new Wallet(process.env.WALLET_PRIVATE_KEY!, provider);
  const deployer = new Deployer(hre, wallet);

  const subscriptionManagerArtifact = await deployer.loadArtifact(
    "SubscriptionManager"
  );

  const subscriptionManager = await deployer.deploy(
    subscriptionManagerArtifact,
    [process.env.PRICE_FEED_ADDRESS!]
  );
  console.log("SubscriptionManager deployed at:", subscriptionManager.address);

  const envConfig = dotenv.parse(fs.readFileSync(".env"));
  envConfig.SUBSCRIPTION_MANAGER_ADDRESS = subscriptionManager.address;
  fs.writeFileSync(
    ".env",
    Object.entries(envConfig)
      .map(([key, val]) => `${key}=${val}`)
      .join("\n")
  );

  const contractFullyQualifiedName =
    "contracts/SubscriptionManager.sol:SubscriptionManager";
  await hre.run("verify:verify", {
    address: subscriptionManager.address,
    contract: contractFullyQualifiedName,
    constructorArguments: [process.env.PRICE_FEED_ADDRESS!],
    bytecode: subscriptionManagerArtifact.bytecode,
  });
  console.log(`${contractFullyQualifiedName} verified!`);
}
