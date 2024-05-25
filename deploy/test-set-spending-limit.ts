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

  let setLimitTx = await account.populateTransaction.setSpendingLimit(
    utils.ETH_ADDRESS,
    ethers.utils.parseEther("0.1")
  );
  setLimitTx = {
    ...setLimitTx,
    from: owner.address,
    chainId: (await provider.getNetwork()).chainId,
    nonce: await provider.getTransactionCount(owner.address),
    type: 113,
    customData: {
      gasPerPubdata: utils.DEFAULT_GAS_PER_PUBDATA_LIMIT,
    } as types.Eip712Meta,
    value: ethers.BigNumber.from(0),
  };

  setLimitTx.gasPrice = await provider.getGasPrice();
  setLimitTx.gasLimit = await provider.estimateGas(setLimitTx);

  const signedTxHash = EIP712Signer.getSignedDigest(setLimitTx);
  const signature = ethers.utils.arrayify(
    ethers.utils.joinSignature(owner._signingKey().signDigest(signedTxHash))
  );

  setLimitTx.customData = {
    ...setLimitTx.customData,
    customSignature: signature,
  };

  console.log("Setting spending limit for the SubscriptionAccount...");
  const sentTx = await provider.sendTransaction(utils.serialize(setLimitTx));
  await sentTx.wait();

  console.log("Spending limit set successfully");
}
