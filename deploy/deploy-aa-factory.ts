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

  const factoryArtifact = await deployer.loadArtifact("AAFactory");
  const aaArtifact = await deployer.loadArtifact("SubscriptionAccount");
  const bytecodeHash = utils.hashBytecode(aaArtifact.bytecode);

  const factory = await deployer.deploy(
    factoryArtifact,
    [bytecodeHash],
    undefined,
    [aaArtifact.bytecode]
  );
  console.log("AAFactory deployed at:", factory.address);

  const updateEnvFile = (
    filePath: string,
    prependNextPublic: boolean = false
  ) => {
    const envConfig = dotenv.parse(fs.readFileSync(filePath));
    const key = prependNextPublic
      ? "NEXT_PUBLIC_AA_FACTORY_ADDRESS"
      : "AA_FACTORY_ADDRESS";
    envConfig[key] = factory.address;
    fs.writeFileSync(
      filePath,
      Object.entries(envConfig)
        .map(([key, val]) => `${key}=${val}`)
        .join("\n")
    );
  };

  // Update .env in backend root
  const backendEnvPath = path.resolve(__dirname, "..", ".env");
  updateEnvFile(backendEnvPath);

  // Update .env in app directory
  const appEnvPath = path.resolve(__dirname, "..", "..", "app", ".env");
  updateEnvFile(appEnvPath, true);

  // Verify contract
  const contractFullyQualifiedName = "contracts/AAFactory.sol:AAFactory";
  try {
    await hre.run("verify:verify", {
      address: factory.address,
      contract: contractFullyQualifiedName,
      constructorArguments: [bytecodeHash],
      bytecode: factoryArtifact.bytecode,
    });
    console.log(`${contractFullyQualifiedName} verified!`);
  } catch (error) {
    console.error(
      `Verification failed for ${contractFullyQualifiedName}:`,
      error
    );
  }
}
