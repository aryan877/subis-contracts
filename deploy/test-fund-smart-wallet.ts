import { Wallet, Provider } from "zksync-web3";
import * as ethers from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import * as dotenv from "dotenv";

export default async function (hre: HardhatRuntimeEnvironment) {
  dotenv.config();

  // @ts-ignore target zkSyncTestnet in config file which can be testnet or local
  const provider = new Provider(hre.config.networks.zkSyncTestnet.url);
  const wallet = new Wallet(process.env.WALLET_PRIVATE_KEY!, provider);

  const subscriptionAccountAddress = process.env.SUBSCRIPTION_ACCOUNT_ADDRESS!;

  if (!subscriptionAccountAddress) {
    throw new Error(
      "Subscription account address not provided in the .env file"
    );
  }

  console.log("Funding subscription account with ETH...");
  const tx = await wallet.sendTransaction({
    to: subscriptionAccountAddress,
    value: ethers.utils.parseEther("1"),
  });

  await tx.wait();

  console.log("Subscription account funded with ETH");

  const subscriptionAccountBalance = await provider.getBalance(
    subscriptionAccountAddress
  );
  console.log(
    `Subscription account ETH balance is now ${ethers.utils.formatEther(
      subscriptionAccountBalance
    )} ETH`
  );
}
