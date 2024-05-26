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

  const subscriptionManagerArtifact = await hre.artifacts.readArtifact(
    "SubscriptionManager"
  );
  const subscriptionManager = new Contract(
    subscriptionManagerAddress,
    subscriptionManagerArtifact.abi,
    owner
  );

  // Get the subscription fee in USD from the contract
  const subscriptionFeeUSD = await subscriptionManager.getSubscriptionFee(
    planId
  );
  const subscriptionFeeWei = await subscriptionManager.convertUSDtoETH(
    subscriptionFeeUSD
  );

  console.log(ethers.utils.formatUnits(subscriptionFeeWei, 18));

  // Estimate the gas cost for the transaction
  const gasPrice = await provider.getGasPrice();
  const gasLimit = await provider.estimateGas({
    from: subscriptionAccountAddress,
    to: subscriptionManagerAddress,
    value: subscriptionFeeWei,
    data: subscriptionManager.interface.encodeFunctionData(
      "startSubscription",
      [planId]
    ),
  });
  const gasCost = gasPrice.mul(gasLimit);

  // Calculate the amount to send including gas cost
  const totalAmount = subscriptionFeeWei.add(gasCost);

  // Ensure there are enough funds to cover the total cost
  const subscriptionAccountBalance = await provider.getBalance(
    subscriptionAccountAddress
  );
  if (subscriptionAccountBalance.lt(totalAmount)) {
    console.error(
      "Insufficient balance to cover subscription fee and gas cost."
    );
    return;
  }

  // Populate the transaction
  let executeTransactionTx = {
    from: subscriptionAccountAddress,
    to: subscriptionManagerAddress,
    chainId: (await provider.getNetwork()).chainId,
    nonce: await provider.getTransactionCount(subscriptionAccountAddress),
    type: 113,
    customData: {
      gasPerPubdata: utils.DEFAULT_GAS_PER_PUBDATA_LIMIT,
    } as types.Eip712Meta,
    value: subscriptionFeeWei,
    data: subscriptionManager.interface.encodeFunctionData(
      "startSubscription",
      [planId]
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

  console.log("Executing transaction to start subscription and pay fee...");
  const sentTx = await provider.sendTransaction(
    utils.serialize(executeTransactionTx)
  );
  await sentTx.wait();

  console.log("Subscription fee paid successfully and subscription started");
}
