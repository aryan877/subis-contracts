import { Wallet, Provider, Contract } from "zksync-web3";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import * as dotenv from "dotenv";
import { ethers } from "ethers";

export default async function (hre: HardhatRuntimeEnvironment) {
  dotenv.config();
  // @ts-ignore target zkSyncTestnet in config file which can be testnet or local
  const provider = new Provider(hre.config.networks.zkSyncTestnet.url);
  const owner = new Wallet(process.env.WALLET_PRIVATE_KEY!, provider);
  const subscriptionAccountAddress = process.env.SUBSCRIPTION_ACCOUNT_ADDRESS!;

  const accountArtifact = await hre.artifacts.readArtifact(
    "SubscriptionAccount"
  );
  const subscriptionAccount = new Contract(
    subscriptionAccountAddress,
    accountArtifact.abi,
    owner
  );

  const balanceWei = await provider.getBalance(subscriptionAccountAddress);
  console.log(
    `Balance of the smart contract account: ${ethers.utils.formatEther(
      balanceWei
    )} ETH`
  );

  const gasPrice = await provider.getGasPrice();
  const estimatedGasLimit = await subscriptionAccount.estimateGas.withdraw(
    balanceWei,
    { from: owner.address }
  );
  const gasCost = gasPrice.mul(estimatedGasLimit);

  console.log(`Estimated Gas Cost: ${ethers.utils.formatEther(gasCost)} ETH`);

  const amountToWithdraw = balanceWei.sub(gasCost);

  if (amountToWithdraw.lte(ethers.constants.Zero)) {
    console.error("Insufficient balance to cover gas cost.");
    return;
  }
  console.log(
    `Withdrawing ${ethers.utils.formatEther(
      amountToWithdraw
    )} ETH from SubscriptionAccount to owner...`
  );
  const tx = await subscriptionAccount.withdraw(amountToWithdraw);
  await tx.wait();

  console.log("Funds withdrawn successfully.");
}
