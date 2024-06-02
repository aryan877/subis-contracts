import { Wallet, Provider, Contract, utils } from "zksync-web3";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import * as dotenv from "dotenv";
import { ethers } from "ethers";

export default async function (hre: HardhatRuntimeEnvironment) {
  dotenv.config();

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

  console.log("Charging expired subscriptions...");

  let chargeExpiredTx =
    await subscriptionManager.populateTransaction.chargeExpiredSubscriptions();

  chargeExpiredTx = {
    ...chargeExpiredTx,
    from: await owner.getAddress(),
    chainId: (await provider.getNetwork()).chainId,
    nonce: await provider.getTransactionCount(await owner.getAddress()),
    type: 113,
    customData: {
      gasPerPubdata: utils.DEFAULT_GAS_PER_PUBDATA_LIMIT,
    },
    value: ethers.BigNumber.from(0),
  };

  chargeExpiredTx.gasPrice = await provider.getGasPrice();
  chargeExpiredTx.gasLimit = await provider.estimateGas(chargeExpiredTx);

  const txCost = chargeExpiredTx.gasPrice.mul(chargeExpiredTx.gasLimit);

  console.log(`Estimated gas: ${chargeExpiredTx.gasLimit.toString()}`);
  console.log(
    `Gas price: ${ethers.utils.formatUnits(
      chargeExpiredTx.gasPrice,
      "gwei"
    )} gwei`
  );
  console.log(
    `Estimated transaction cost: ${ethers.utils.formatEther(txCost)} ETH`
  );

  const tx = await owner.sendTransaction(chargeExpiredTx);
  console.log("Transaction sent. Waiting for confirmation...");
  await tx.wait();

  console.log("Expired subscriptions charged successfully");
}
