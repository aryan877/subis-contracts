import { Wallet, Provider, Contract } from "zksync-web3";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { ethers } from "ethers";

export default async function (hre: HardhatRuntimeEnvironment) {
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

  const latestPriceHex = await subscriptionManager.getLatestPrice();
  const latestPrice = ethers.BigNumber.from(latestPriceHex);

  // Convert the price to a decimal string with 8 decimal places
  const latestPriceDecimal = ethers.utils.formatUnits(latestPrice, 8);

  console.log("Latest ETH/USD Price:", latestPriceDecimal);
}
