import { ethers } from "ethers";
import * as fs from "fs";
import { Provider, Wallet } from "zksync-web3";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import dotenv from "dotenv";

dotenv.config();

const PRIVATE_KEY = process.env.WALLET_PRIVATE_KEY || "";
const SUBSCRIPTION_MANAGER_ADDRESS =
  process.env.SUBSCRIPTION_MANAGER_ADDRESS || "";

if (!PRIVATE_KEY)
  throw new Error("⛔️ Private key not detected! Add it to the .env file!");
if (!SUBSCRIPTION_MANAGER_ADDRESS)
  throw new Error(
    "⛔️ SUBSCRIPTION_MANAGER_ADDRESS not detected! Add it to the .env file!"
  );

export default async function (hre: HardhatRuntimeEnvironment) {
  console.log(
    `Running deploy script for the SubscriptionPaymaster contract...`
  );

  // @ts-ignore target zkSyncTestnet in config file which can be testnet or local
  const provider = new Provider(hre.config.networks.zkSyncTestnet.url);
  const wallet = new Wallet(PRIVATE_KEY, provider);
  const deployer = new Deployer(hre, wallet);
  const paymasterArtifact = await deployer.loadArtifact(
    "SubscriptionPaymaster"
  );

  const deploymentFee = await deployer.estimateDeployFee(paymasterArtifact, [
    SUBSCRIPTION_MANAGER_ADDRESS,
  ]);
  const parsedFee = ethers.utils.formatEther(deploymentFee.toString());
  console.log(`The deployment is estimated to cost ${parsedFee} ETH`);

  const paymaster = await deployer.deploy(paymasterArtifact, [
    SUBSCRIPTION_MANAGER_ADDRESS,
  ]);
  console.log(`Paymaster address: ${paymaster.address}`);

  console.log("Funding paymaster with ETH");
  await wallet
    .sendTransaction({
      to: paymaster.address,
      value: ethers.utils.parseEther("1"),
    })
    .then((tx) => tx.wait());

  const paymasterBalance = await provider.getBalance(paymaster.address);
  console.log(
    `Paymaster ETH balance is now ${ethers.utils.formatEther(
      paymasterBalance
    )} ETH`
  );

  const envConfig = dotenv.parse(fs.readFileSync(".env"));
  envConfig.PAYMASTER_ADDRESS = paymaster.address;

  fs.writeFileSync(
    ".env",
    Object.entries(envConfig)
      .map(([key, val]) => `${key}=${val}`)
      .join("\n")
  );

  const contractFullyQualifiedName =
    "contracts/SubscriptionPaymaster.sol:SubscriptionPaymaster";
  await hre.run("verify:verify", {
    address: paymaster.address,
    contract: contractFullyQualifiedName,
    constructorArguments: [SUBSCRIPTION_MANAGER_ADDRESS],
    bytecode: paymasterArtifact.bytecode,
  });

  console.log("Deployment and verification complete.");
}
