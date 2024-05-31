import { utils, Wallet, Provider } from "zksync-web3";
import * as ethers from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import * as dotenv from "dotenv";
import * as fs from "fs";

export default async function (hre: HardhatRuntimeEnvironment) {
  dotenv.config();

  // @ts-ignore target zkSyncTestnet in config file which can be testnet or local
  const provider = new Provider(hre.config.networks.zkSyncTestnet.url);
  const wallet = new Wallet(process.env.WALLET_PRIVATE_KEY!, provider);

  const factoryAddress = process.env.MANAGER_FACTORY_ADDRESS!;
  const priceFeedAddress = process.env.PRICE_FEED_ADDRESS!;
  const factoryArtifact = await hre.artifacts.readArtifact("ManagerFactory");
  const managerFactory = new ethers.Contract(
    factoryAddress,
    factoryArtifact.abi,
    wallet
  );

  const owner = wallet.address;
  console.log("Subscription Manager owner:", owner);

  const salt = ethers.constants.HashZero;
  const tx = await managerFactory.deployManager(salt, owner, priceFeedAddress);
  await tx.wait();

  const abiCoder = new ethers.utils.AbiCoder();
  const subscriptionManagerAddress = utils.create2Address(
    factoryAddress,
    await managerFactory.managerBytecodeHash(),
    salt,
    abiCoder.encode(["address", "address"], [owner, priceFeedAddress])
  );
  console.log("SubscriptionManager deployed at:", subscriptionManagerAddress);

  // Store the SubscriptionManager address in the .env file
  const envConfig = dotenv.parse(fs.readFileSync(".env"));
  envConfig.SUBSCRIPTION_MANAGER_ADDRESS = subscriptionManagerAddress;
  fs.writeFileSync(
    ".env",
    Object.entries(envConfig)
      .map(([key, val]) => `${key}=${val}`)
      .join("\n")
  );

  // Verify contract
  const contractFullyQualifiedName =
    "contracts/SubscriptionManager.sol:SubscriptionManager";
  try {
    await hre.run("verify:verify", {
      address: subscriptionManagerAddress,
      contract: contractFullyQualifiedName,
      constructorArguments: [owner, priceFeedAddress],
      bytecode: (
        await hre.artifacts.readArtifact("SubscriptionManager")
      ).bytecode,
    });
    console.log(`${contractFullyQualifiedName} verified!`);
  } catch (error) {
    console.error(
      `Verification failed for ${contractFullyQualifiedName}:`,
      error
    );
  }
}
