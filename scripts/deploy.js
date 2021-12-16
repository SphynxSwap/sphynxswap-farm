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
  const Greeter = await hre.ethers.getContractFactory("BondTeller");
  const greeter = await Greeter.deploy("0x3c043dBE0DE433ccA054a9841A7e17872A75431F", 
    "0x3032d38a2Cd7cfCBfC41B87068C9aC08fC977B78", "0xc81B31262Fb649809BCacb4457997FA4DBae9e84", 
    "0xDB47E4AD8d842e6A32f6e6FD0b278AeEEfD67cC6", "0xA0A2F566E950c2e0c3B90e83B95A7319590eCd5E",
    "0x239BE60B9e0F48EE5a12Ba3145A58381FCF64000");

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
