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

  let unsubscribeTx = await subscriptionManager.populateTransaction.unsubscribe(
    subscriptionAccountAddress,
    planId
  );
  unsubscribeTx = {
    ...unsubscribeTx,
    from: owner.address,
    chainId: (await provider.getNetwork()).chainId,
    nonce: await provider.getTransactionCount(owner.address),
    type: 113,
    customData: {
      gasPerPubdata: utils.DEFAULT_GAS_PER_PUBDATA_LIMIT,
    } as types.Eip712Meta,
    value: ethers.BigNumber.from(0),
  };

  unsubscribeTx.gasPrice = await provider.getGasPrice();
  unsubscribeTx.gasLimit = await provider.estimateGas(unsubscribeTx);

  const signedTxHash = EIP712Signer.getSignedDigest(unsubscribeTx);
  const signature = ethers.utils.arrayify(
    ethers.utils.joinSignature(owner._signingKey().signDigest(signedTxHash))
  );

  unsubscribeTx.customData = {
    ...unsubscribeTx.customData,
    customSignature: signature,
  };

  console.log("Unsubscribing account...");
  const sentTx = await provider.sendTransaction(utils.serialize(unsubscribeTx));
  await sentTx.wait();

  console.log("Unsubscribed successfully from plan", planId);
}