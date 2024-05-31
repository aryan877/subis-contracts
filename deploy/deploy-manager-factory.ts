import { utils, Wallet, Provider } from "zksync-web3";
import * as ethers from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import * as dotenv from "dotenv";
import * as fs from "fs";
import * as path from "path";

export default async function (hre: HardhatRuntimeEnvironment) {
  dotenv.config();
  // @ts-ignore target zkSyncTestnet in config file which can be testnet or local
  const provider = new Provider(hre.config.networks.zkSyncTestnet.url);
  const wallet = new Wallet(process.env.WALLET_PRIVATE_KEY!, provider);
  const deployer = new Deployer(hre, wallet);

  const managerFactoryArtifact = await deployer.loadArtifact("ManagerFactory");
  const subscriptionManagerArtifact = await deployer.loadArtifact(
    "SubscriptionManager"
  );
  const managerBytecodeHash = utils.hashBytecode(
    subscriptionManagerArtifact.bytecode
  );

  const managerFactory = await deployer.deploy(
    managerFactoryArtifact,
    [managerBytecodeHash],
    undefined,
    [subscriptionManagerArtifact.bytecode]
  );
  console.log("ManagerFactory deployed at:", managerFactory.address);

  // Update .env in backend root
  const backendEnvPath = path.resolve(__dirname, "..", ".env");
  const appEnvPath = path.resolve(__dirname, "..", "..", "app", ".env");

  const updateEnvFile = (
    filePath: string,
    prependNextPublic: boolean = false
  ) => {
    const envConfig = dotenv.parse(fs.readFileSync(filePath));
    const key = prependNextPublic
      ? "NEXT_PUBLIC_MANAGER_FACTORY_ADDRESS"
      : "MANAGER_FACTORY_ADDRESS";
    envConfig[key] = managerFactory.address;
    fs.writeFileSync(
      filePath,
      Object.entries(envConfig)
        .map(([key, val]) => `${key}=${val}`)
        .join("\n")
    );
  };

  // Update both .env files
  updateEnvFile(backendEnvPath);
  updateEnvFile(appEnvPath, true);

  // Verify contract
  const contractFullyQualifiedName =
    "contracts/ManagerFactory.sol:ManagerFactory";
  try {
    await hre.run("verify:verify", {
      address: managerFactory.address,
      contract: contractFullyQualifiedName,
      constructorArguments: [managerBytecodeHash],
      bytecode: managerFactoryArtifact.bytecode,
    });
    console.log(`${contractFullyQualifiedName} verified!`);
  } catch (error) {
    console.error(
      `Verification failed for ${contractFullyQualifiedName}:`,
      error
    );
  }
}
