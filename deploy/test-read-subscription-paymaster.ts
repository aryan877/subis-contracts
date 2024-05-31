import { Wallet, Provider, Contract } from "zksync-web3";
import { HardhatRuntimeEnvironment } from "hardhat/types";

export default async function (hre: HardhatRuntimeEnvironment) {
  // @ts-ignore target zkSyncTestnet in config file which can be testnet or local
  const provider = new Provider(hre.config.networks.zkSyncTestnet.url);
  const owner = new Wallet(process.env.WALLET_PRIVATE_KEY!, provider);
  const subscriptionManagerAddress = process.env.SUBSCRIPTION_MANAGER_ADDRESS!;

  const managerArtifact = await hre.artifacts.readArtifact(
    "SubscriptionManager"
  );
  const subscriptionManager = new Contract(
    subscriptionManagerAddress,
    managerArtifact.abi,
    owner
  );

  // Get the Paymaster address of the SubscriptionManager
  const paymasterAddress = await subscriptionManager.paymaster();
  console.log(
    `Paymaster address of the SubscriptionManager: ${paymasterAddress}`
  );
}
