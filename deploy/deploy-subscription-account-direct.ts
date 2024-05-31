import { utils, Wallet, Provider, ContractFactory } from "zksync-web3";
import * as ethers from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import * as dotenv from "dotenv";
import * as fs from "fs";

export default async function (hre: HardhatRuntimeEnvironment) {
  dotenv.config();

  // @ts-ignore target zkSyncTestnet in config file which can be testnet or local
  const provider = new Provider(hre.config.networks.zkSyncTestnet.url);
  const wallet = new Wallet(process.env.WALLET_PRIVATE_KEY!, provider);
  const subscriptionManagerAddress = process.env.SUBSCRIPTION_MANAGER_ADDRESS!;

  const owner = wallet.address;
  console.log("Subscription Account owner:", owner);

  // Read the SubscriptionAccount artifact
  const subscriptionAccountArtifact = await hre.artifacts.readArtifact(
    "SubscriptionAccount"
  );

  // Deploy the SubscriptionAccount contract using createAccount
  const contractFactory = new ContractFactory(
    subscriptionAccountArtifact.abi,
    subscriptionAccountArtifact.bytecode,
    wallet,
    "createAccount"
  );

  console.log("Deploying SubscriptionAccount...");
  const subscriptionAccount = await contractFactory.deploy(
    owner,
    subscriptionManagerAddress
  );
  await subscriptionAccount.deployed();

  const subscriptionAccountAddress = subscriptionAccount.address;
  console.log("SubscriptionAccount deployed at:", subscriptionAccountAddress);

  // Fund the SubscriptionAccount with ETH
  await (
    await wallet.sendTransaction({
      to: subscriptionAccountAddress,
      value: ethers.utils.parseEther("0.001"),
    })
  ).wait();
  console.log("SubscriptionAccount funded with ETH");

  // Store the SubscriptionAccount address in the .env file
  const envConfig = dotenv.parse(fs.readFileSync(".env"));
  envConfig.SUBSCRIPTION_ACCOUNT_ADDRESS = subscriptionAccountAddress;
  fs.writeFileSync(
    ".env",
    Object.entries(envConfig)
      .map(([key, val]) => `${key}=${val}`)
      .join("\n")
  );

  // Verify contract
  const contractFullyQualifiedName =
    "contracts/SubscriptionAccount.sol:SubscriptionAccount";
  try {
    await hre.run("verify:verify", {
      address: subscriptionAccountAddress,
      contract: contractFullyQualifiedName,
      constructorArguments: [owner, subscriptionManagerAddress],
      bytecode: subscriptionAccountArtifact.bytecode,
    });
    console.log(`${contractFullyQualifiedName} verified!`);
  } catch (error) {
    console.error(
      `Verification failed for ${contractFullyQualifiedName}:`,
      error
    );
  }
}
