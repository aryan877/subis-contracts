import { utils, Wallet, Provider } from "zksync-web3";
import * as ethers from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import * as dotenv from "dotenv";
import * as fs from "fs";

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

  const envConfig = dotenv.parse(fs.readFileSync(".env"));
  envConfig.AA_FACTORY_ADDRESS = factory.address;
  fs.writeFileSync(
    ".env",
    Object.entries(envConfig)
      .map(([key, val]) => `${key}=${val}`)
      .join("\n")
  );

  // Verify contract
  const contractFullyQualifiedName = "contracts/AAFactory.sol:AAFactory";
  await hre.run("verify:verify", {
    address: factory.address,
    contract: contractFullyQualifiedName,
    constructorArguments: [bytecodeHash],
    bytecode: factoryArtifact.bytecode,
  });
  console.log(`${contractFullyQualifiedName} verified!`);
}
