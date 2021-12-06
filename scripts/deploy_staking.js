const { ethers } = require("hardhat");

async function main() {

    const [deployer] = await ethers.getSigners();
    console.log('Deploying contracts with the account: ' + deployer.address);

    const firstEpochNumber = "550";
    const firstBlockNumber = "9505000";
    
    const Authority = await ethers.getContractFactory("SphynxAuthority");
    const authority = await Authority.deploy(
        deployer.address,
        deployer.address,
        deployer.address,
        deployer.address
    );

    console.log('authority address = : ' + authority.address);
    
    const OHM = await ethers.getContractFactory('SphynxERC20Token');
    const ohm = await OHM.deploy(authority.address);

    console.log('ohm address = : ' + ohm.address);

    const SphynxTreasury = await ethers.getContractFactory('SphynxTreasury');
    const olympusTreasury = await SphynxTreasury.deploy(ohm.address, '0', authority.address);
    console.log('olympusTreasury address = : ' + olympusTreasury.address);

    const SOHM = await ethers.getContractFactory('sSphynx');
    const sOHM = await SOHM.deploy();

    console.log('sOHM address = : ' + sOHM.address);

    const GOHM = await ethers.getContractFactory("gOHM");
    const gOHM = await GOHM.deploy(sOHM.address);

    console.log('gOHM address = : ' + gOHM.address);


    const SphynxStaking = await ethers.getContractFactory('SphynxStaking');
    const staking = await SphynxStaking.deploy(ohm.address, sOHM.address, gOHM.address, '2200', firstEpochNumber, firstBlockNumber, authority.address);
    console.log('staking address = : ' + staking.address);

    const Distributor = await ethers.getContractFactory('Distributor');
    const distributor = await Distributor.deploy(olympusTreasury.address, ohm.address, staking.address, authority.address );
    console.log('distributor address = : ' + distributor.address);

    await sOHM.setIndex('7675210820');
    console.log('distributor address = : ' + distributor.address);
    await sOHM.setgOHM(gOHM.address);
    console.log('distributor address = : ' + distributor.address);
    await sOHM.initialize(staking.address, olympusTreasury.address);
    console.log('distributor address = : ' + distributor.address);
    console.log("OHM: " + ohm.address);
    console.log("Sphynx Treasury: " + olympusTreasury.address);
    console.log("Staked Sphynx: " + sOHM.address);
    console.log("Staking Contract: " + staking.address);
    console.log("Distributor: " + distributor.address);
}

main()
    .then(() => process.exit())
    .catch(error => {
        console.error(error);
        process.exit(1);
})