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
  const Greeter = await hre.ethers.getContractFactory("SphynxVault");
  const greeter = await Greeter.deploy("0xd38ec16caf3464ca04929e847e4550dcff25b27a", "0xd38ec16caf3464ca04929e847e4550dcff25b27a", "0x39dDE712D0B08C3Ce11AF7bd5b6E2ef9A495D3Be", "0x627a91E56434801B695F46DB4c1140567aF990C5", "0x074222A8A5b6A155A80C533A54E3ef5ED267AE16");

  await greeter.deployed();

  console.log("Greeter deployed to:", greeter.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
