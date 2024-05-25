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

  const accountArtifact = await hre.artifacts.readArtifact(
    "SubscriptionAccount"
  );
  const account = new Contract(
    subscriptionAccountAddress,
    accountArtifact.abi,
    owner
  );

  // Get the current balance of the SubscriptionAccount
  const subscriptionAccountBalance = await provider.getBalance(
    subscriptionAccountAddress
  );

  // Estimate the gas cost for the transaction
  const gasPrice = await provider.getGasPrice();
  const gasLimit = await provider.estimateGas({
    from: subscriptionAccountAddress,
    to: owner.address,
    value: subscriptionAccountBalance,
    data: "0x",
  });
  const gasCost = gasPrice.mul(gasLimit);

  // Calculate the amount to send after deducting gas cost
  const amountToSend = subscriptionAccountBalance.sub(gasCost);

  // Ensure there are enough funds to cover gas cost
  if (amountToSend.lte(ethers.constants.Zero)) {
    console.error("Insufficient balance to cover gas cost.");
    return;
  }

  let executeTransactionTx = {
    from: subscriptionAccountAddress,
    to: owner.address,
    chainId: (await provider.getNetwork()).chainId,
    nonce: await provider.getTransactionCount(subscriptionAccountAddress),
    type: 113,
    customData: {
      gasPerPubdata: utils.DEFAULT_GAS_PER_PUBDATA_LIMIT,
    } as types.Eip712Meta,
    value: amountToSend,
    data: "0x",
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
    "Executing transaction to send remaining funds from SubscriptionAccount to owner..."
  );

  const sentTx = await provider.sendTransaction(
    utils.serialize(executeTransactionTx)
  );
  await sentTx.wait();

  console.log("Remaining funds sent successfully");
}
