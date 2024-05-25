import {
  utils,
  Wallet,
  Provider,
  Contract,
  EIP712Signer,
  types,
} from "zksync-web3";
import * as ethers from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";

export default async function (hre: HardhatRuntimeEnvironment) {
  // @ts-ignore target zkSyncTestnet in config file which can be testnet or local
  const provider = new Provider(hre.config.networks.zkSyncTestnet.url);
  const owner = new Wallet(process.env.WALLET_PRIVATE_KEY!, provider);
  const subscriptionAccountAddress = process.env.SUBSCRIPTION_ACCOUNT_ADDRESS!;
  const subscriptionManagerAddress = process.env.SUBSCRIPTION_MANAGER_ADDRESS!;
  const planId = parseInt(process.env.PLAN_ID!, 10);

  const accountArtifact = await hre.artifacts.readArtifact(
    "SubscriptionAccount"
  );
  const account = new Contract(
    subscriptionAccountAddress,
    accountArtifact.abi,
    owner
  );

  const subscriptionManagerArtifact = await hre.artifacts.readArtifact(
    "SubscriptionManager"
  );
  const subscriptionManager = new Contract(
    subscriptionManagerAddress,
    subscriptionManagerArtifact.abi,
    owner
  );
  const subscriptionFeeUSD = await subscriptionManager.getSubscriptionFee(
    planId
  );
  console.log(
    `Subscription fee in USD: ${ethers.utils.formatUnits(
      subscriptionFeeUSD,
      8
    )}`
  );

  // Convert the subscription fee from USD to ETH (not needed to send in transaction)
  const subscriptionFeeWei = await account.convertUSDtoETH(subscriptionFeeUSD);
  const subscriptionFeeETH = ethers.utils.formatEther(subscriptionFeeWei);
  console.log(`Subscription fee: ${subscriptionFeeETH} ETH`);

  const gasPrice = await provider.getGasPrice();
  const gasLimit = await provider.estimateGas({
    from: subscriptionAccountAddress,
    to: subscriptionManagerAddress,
    value: 0,
    data: "0x",
  });

  let executeTransactionTx = {
    from: subscriptionAccountAddress,
    to: subscriptionManagerAddress,
    chainId: (await provider.getNetwork()).chainId,
    nonce: await provider.getTransactionCount(subscriptionAccountAddress),
    type: 113,
    customData: {
      gasPerPubdata: utils.DEFAULT_GAS_PER_PUBDATA_LIMIT,
    } as types.Eip712Meta,
    value: 0,
    data: subscriptionManager.interface.encodeFunctionData(
      "processSubscriptionPayment",
      [subscriptionAccountAddress, planId]
    ),
    gasPrice: gasPrice,
    gasLimit: gasLimit,
  };

  const signedTxHash = EIP712Signer.getSignedDigest(executeTransactionTx);
  const signature = ethers.utils.joinSignature(
    owner._signingKey().signDigest(signedTxHash)
  );

  executeTransactionTx.customData = {
    ...executeTransactionTx.customData,
    customSignature: signature,
  };

  console.log(
    "Executing transaction to pay subscription fee from SubscriptionAccount to SubscriptionManager..."
  );

  const sentTx = await provider.sendTransaction(
    utils.serialize(executeTransactionTx)
  );
  await sentTx.wait();

  console.log("Subscription fee paid successfully");
}
