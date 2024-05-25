import { Wallet, Provider, Contract } from "zksync-web3";
import { HardhatRuntimeEnvironment } from "hardhat/types";

export default async function (hre: HardhatRuntimeEnvironment) {
  // @ts-ignore target zkSyncTestnet in config file which can be testnet or local
  const provider = new Provider(hre.config.networks.zkSyncTestnet.url);
  const owner = new Wallet(process.env.WALLET_PRIVATE_KEY!, provider);
  const subscriptionAccountAddress = process.env.SUBSCRIPTION_ACCOUNT_ADDRESS!;

  const accountArtifact = await hre.artifacts.readArtifact(
    "SubscriptionAccount"
  );
  const account = new Contract(
    subscriptionAccountAddress,
    accountArtifact.abi,
    owner
  );

  // Get the owner of the SubscriptionAccount
  const accountOwner = await account.owner();
  console.log(`Owner of the SubscriptionAccount: ${accountOwner}`);
}
