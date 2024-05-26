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
import dotenv from "dotenv";

dotenv.config();

const PAYMASTER_ADDRESS = process.env.PAYMASTER_ADDRESS!;
const SUBSCRIPTION_ACCOUNT_ADDRESS = process.env.SUBSCRIPTION_ACCOUNT_ADDRESS!;
const SUBSCRIPTION_MANAGER_ADDRESS = process.env.SUBSCRIPTION_MANAGER_ADDRESS!;
const PLAN_ID = parseInt(process.env.PLAN_ID!, 10);

export default async function (hre: HardhatRuntimeEnvironment) {
  // @ts-ignore target zkSyncTestnet in config file which can be testnet or local
  const provider = new Provider(hre.config.networks.zkSyncTestnet.url);
  const owner = new Wallet(process.env.WALLET_PRIVATE_KEY!, provider);

  const subscriptionManagerArtifact = await hre.artifacts.readArtifact(
    "SubscriptionManager"
  );
  const subscriptionManager = new Contract(
    SUBSCRIPTION_MANAGER_ADDRESS,
    subscriptionManagerArtifact.abi,
    owner
  );

  const paymasterParams = utils.getPaymasterParams(PAYMASTER_ADDRESS, {
    type: "General",
    innerInput: new Uint8Array(),
  });

  let subscribeTx = await subscriptionManager.populateTransaction.subscribe(
    PLAN_ID
  );
  subscribeTx = {
    ...subscribeTx,
    from: SUBSCRIPTION_ACCOUNT_ADDRESS,
    chainId: (await provider.getNetwork()).chainId,
    nonce: await provider.getTransactionCount(SUBSCRIPTION_ACCOUNT_ADDRESS),
    type: 113,
    customData: {
      gasPerPubdata: utils.DEFAULT_GAS_PER_PUBDATA_LIMIT,
      paymasterParams: paymasterParams,
    } as types.Eip712Meta,
    value: ethers.BigNumber.from(0),
  };

  subscribeTx.gasPrice = await provider.getGasPrice();
  subscribeTx.gasLimit = await provider.estimateGas(subscribeTx);

  const signedTxHash = EIP712Signer.getSignedDigest(subscribeTx);
  const signature = ethers.utils.arrayify(
    ethers.utils.joinSignature(owner._signingKey().signDigest(signedTxHash))
  );

  subscribeTx.customData = {
    ...subscribeTx.customData,
    customSignature: signature,
  };

  console.log("Subscribing account to plan...");
  const sentTx = await provider.sendTransaction(utils.serialize(subscribeTx));
  await sentTx.wait();

  console.log("Subscribed successfully to plan", PLAN_ID);
}
