import { ethers } from "ethers";
import { Provider, Wallet } from "zksync-web3";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import dotenv from "dotenv";

dotenv.config();

const PRIVATE_KEY = process.env.WALLET_PRIVATE_KEY || "";
const PAYMASTER_ADDRESS = process.env.PAYMASTER_ADDRESS || "";

if (!PRIVATE_KEY)
  throw new Error("⛔️ Private key not detected! Add it to the .env file!");
if (!PAYMASTER_ADDRESS)
  throw new Error(
    "⛔️ PAYMASTER_ADDRESS not detected! Add it to the .env file!"
  );

async function fundPaymaster(hre: HardhatRuntimeEnvironment) {
  // @ts-ignore target zkSyncTestnet in config file which can be testnet or local
  const provider = new Provider(hre.config.networks.zkSyncTestnet.url);
  const wallet = new Wallet(PRIVATE_KEY, provider);

  console.log("Funding paymaster with ETH...");
  await wallet
    .sendTransaction({
      to: PAYMASTER_ADDRESS,
      value: ethers.utils.parseEther("0.005"),
    })
    .then((tx) => tx.wait());

  const paymasterBalance = await provider.getBalance(PAYMASTER_ADDRESS);
  console.log(
    `Paymaster ETH balance is now ${ethers.utils.formatEther(
      paymasterBalance
    )} ETH`
  );
}

export default async function (hre: HardhatRuntimeEnvironment) {
  try {
    await fundPaymaster(hre);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}
