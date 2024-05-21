import { utils, Wallet, Provider } from "zksync-web3";
import * as ethers from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import dotenv from "dotenv";

dotenv.config();

const PRIVATE_KEY = process.env.WALLET_PRIVATE_KEY || "";

if (!PRIVATE_KEY) {
  throw new Error("⛔️ Private key not detected! Add it to the .env file!");
}

export default async function (hre: HardhatRuntimeEnvironment) {
  console.log("Running deploy script for the SubscriptionEscrow contracts...");

  // Initialize the wallet.
  // @ts-ignore target zkSyncTestnet in config file which can be testnet or local
  const provider = new Provider(hre.config.networks.zkSyncTestnet.url);
  const wallet = new Wallet(PRIVATE_KEY, provider);

  const deployer = new Deployer(hre, wallet);
  const factoryArtifact = await deployer.loadArtifact(
    "SubscriptionEscrowFactory"
  );
  const escrowArtifact = await deployer.loadArtifact("SubscriptionEscrow");

  // Deploy the factory contract.
  const factory = await deployer.deploy(
    factoryArtifact,
    [utils.hashBytecode(escrowArtifact.bytecode)],
    undefined,
    [escrowArtifact.bytecode]
  );
  console.log(`SubscriptionEscrowFactory address: ${factory.address}`);

  // Verify the SubscriptionEscrowFactory contract.
  const factoryFullyQualifiedName =
    "contracts/SubscriptionEscrowFactory.sol:SubscriptionEscrowFactory";
  const factoryVerificationId = await hre.run("verify:verify", {
    address: factory.address,
    contract: factoryFullyQualifiedName,
    constructorArguments: [utils.hashBytecode(escrowArtifact.bytecode)],
    bytecode: factoryArtifact.bytecode,
  });
  console.log(
    `${factoryFullyQualifiedName} verified! VerificationId: ${factoryVerificationId}`
  );

  const escrowFactory = new ethers.Contract(
    factory.address,
    factoryArtifact.abi,
    wallet
  );
  const owner = wallet;
  console.log("SubscriptionEscrow owner address:", owner.address);

  const salt = ethers.constants.HashZero;
  const subscriptionCancelPeriod = 259200; // 3 days in seconds
  const escrowDisputePeriod = 604800; // 7 days in seconds
  const subscriptionRenewalWindowStart = 1728000; // 20 days in seconds
  const subscriptionRenewalWindowEnd = 2592000; // 30 days in seconds

  const tx = await escrowFactory.deploySubscriptionEscrow(
    salt,
    owner.address,
    subscriptionCancelPeriod,
    escrowDisputePeriod,
    subscriptionRenewalWindowStart,
    subscriptionRenewalWindowEnd
  );
  await tx.wait();

  const abiCoder = new ethers.utils.AbiCoder();
  const escrowAddress = utils.create2Address(
    factory.address,
    await escrowFactory.escrowBytecodeHash(),
    salt,
    abiCoder.encode(
      ["address", "uint256", "uint256", "uint256", "uint256"],
      [
        owner.address,
        subscriptionCancelPeriod,
        escrowDisputePeriod,
        subscriptionRenewalWindowStart,
        subscriptionRenewalWindowEnd,
      ]
    )
  );
  console.log(`SubscriptionEscrow deployed on address ${escrowAddress}`);

  // Verify the SubscriptionEscrow contract.
  const escrowFullyQualifiedName =
    "contracts/SubscriptionEscrow.sol:SubscriptionEscrow";
  const escrowVerificationId = await hre.run("verify:verify", {
    address: escrowAddress,
    contract: escrowFullyQualifiedName,
    constructorArguments: [
      owner.address,
      subscriptionCancelPeriod,
      escrowDisputePeriod,
      subscriptionRenewalWindowStart,
      subscriptionRenewalWindowEnd,
    ],
    bytecode: escrowArtifact.bytecode,
  });
  console.log(
    `${escrowFullyQualifiedName} verified! VerificationId: ${escrowVerificationId}`
  );

  console.log("Funding SubscriptionEscrow contract with some ETH");
  await (
    await owner.sendTransaction({
      to: escrowAddress,
      value: ethers.utils.parseEther("0.02"),
    })
  ).wait();

  console.log("Done!");
}
