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

  const factoryAddress = process.env.AA_FACTORY_ADDRESS!;
  const subscriptionManagerAddress = process.env.SUBSCRIPTION_MANAGER_ADDRESS!;
  const factoryArtifact = await hre.artifacts.readArtifact("AAFactory");
  const aaFactory = new ethers.Contract(
    factoryAddress,
    factoryArtifact.abi,
    wallet
  );

  const owner = wallet.address;
  console.log("Subscription Account owner:", owner);

  const salt = ethers.constants.HashZero;
  const tx = await aaFactory.deployAccount(
    salt,
    owner,
    subscriptionManagerAddress
  );
  await tx.wait();

  const abiCoder = new ethers.utils.AbiCoder();
  const subscriptionAccountAddress = utils.create2Address(
    factoryAddress,
    await aaFactory.aaBytecodeHash(),
    salt,
    abiCoder.encode(["address", "address"], [owner, subscriptionManagerAddress])
  );
  console.log("SubscriptionAccount deployed at:", subscriptionAccountAddress);

  await (
    await wallet.sendTransaction({
      to: subscriptionAccountAddress,
      value: ethers.utils.parseEther("1"),
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
      bytecode: (
        await hre.artifacts.readArtifact("SubscriptionAccount")
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
