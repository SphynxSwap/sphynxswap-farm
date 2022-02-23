// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // We get the contract to deploy
  // const SphynxToken = await hre.ethers.getContractFactory("SphynxToken");
  // const sphynxToken = await SphynxToken.deploy();
  // await sphynxToken.deployed();
  // console.log("SphynxToken deployed to ", sphynxToken.address);
  const MasterChef = await hre.ethers.getContractFactory("SphynxMasterChef");
  const masterChef = await MasterChef.deploy(
    "0xc183062db25fc96325485ea369c979ce881ac0ea",
    "0x04Dc3d07820074CDbE4D1B2b4eF7c095FA52a102",
    "30000",
    "15503750"
  );
  await masterChef.deployed();
  console.log("MasterChef deployed to ", masterChef.address);
  // const SphynxVault = await hre.ethers.getContractFactory("SphynxVault");
  // const sphynxVault = await SphynxVault.deploy(
  //   '0x319DD84F4133bf30e1bB69e99E18f058D8c8daD8',
  //   '0x319DD84F4133bf30e1bB69e99E18f058D8c8daD8',
  //   '0x894e87462b1f444CE5cd0ef46bFd2E4EF181cB51',
  //   "0xf66C2A95567098aa5A4cD8A6B2ECBA6078c42dAc",
  //   "0xf66C2A95567098aa5A4cD8A6B2ECBA6078c42dAc"
  // );
  // await sphynxVault.deployed();
  // console.log("SphynxVault deployed to:", sphynxVault.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
