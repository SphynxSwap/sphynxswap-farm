const { ethers } = require("hardhat");

async function main() {

    const [deployer] = await ethers.getSigners();
    console.log('Deploying contracts with the account: ' + deployer.address);

    const firstEpochNumber = "550";
    const firstBlockNumber = "14987521";
    
    const Authority = await ethers.getContractFactory("SphynxAuthority");
    const authority = await Authority.deploy(
        deployer.address,
        deployer.address,
        deployer.address,
        deployer.address
    );

    console.log('authority address = : ' + authority.address);
    
    const SPH = await ethers.getContractFactory('SphynxERC20Token');
    const sph = await SPH.deploy(authority.address);

    console.log('sphynx address = : ' + sph.address);

    const SphynxTreasury = await ethers.getContractFactory('SphynxTreasury');
    const sphynxTreasury = await SphynxTreasury.deploy(sph.address, '0', authority.address);
    console.log('sphynx Treasury address = : ' + sphynxTreasury.address);

    const BondDepository = await ethers.getContractFactory('SphynxBondDepository');
    const bondDepository = await BondDepository.deploy(sph.address, sphynxTreasury.address, authority.address);
    console.log('bondDepository address = : ' + bondDepository.address);

    const SphynxCalculator = await ethers.getContractFactory('SphynxBondingCalculator');
    const sphynxCalculator = await SphynxCalculator.deploy(sph.address);
    console.log('sphynxCalculator address = : ' + sphynxCalculator.address);

    const SSPH = await ethers.getContractFactory('sSphynx');
    const sSPH = await SSPH.deploy();

    console.log('sSPH address = : ' + sSPH.address);

    const GSPH = await ethers.getContractFactory("gSPH");
    const gSPH = await GSPH.deploy(sSPH.address);

    console.log('gSPH address = : ' + gSPH.address);

    const SphynxStaking = await ethers.getContractFactory('SphynxStaking');
    const staking = await SphynxStaking.deploy(sph.address, sSPH.address, gSPH.address, '2200', firstEpochNumber, firstBlockNumber, authority.address);
    console.log('staking address = : ' + staking.address);

    const Distributor = await ethers.getContractFactory('Distributor');
    const distributor = await Distributor.deploy(sphynxTreasury.address, sph.address, staking.address, authority.address );
    console.log('distributor address = : ' + distributor.address);

    const BondTeller = await ethers.getContractFactory("BondTeller");
    const bondTeller = await BondTeller.deploy(bondDepository.address, staking.address, sphynxTreasury.address, sph.address,
        sSPH.address, authority.address);
    await bondTeller.deployed();
    console.log("bondTeller deployed to:", bondTeller.address);
    // Set staking and sOhm contract as trusted

  
    await sSPH.setIndex('7675210820');
    await sSPH.setgSPH(gSPH.address);
    await sSPH.initialize(staking.address, sphynxTreasury.address);
 
    //  Does this need to happen?
    //await gOhm.migrate(staking.address, sOhm.address);

    // // Initialize sOHM and set the index
    // await sOhm.setIndex(INITIAL_INDEX); // TODO
    // await sOhm.setgOHM(gOhm.address);
    // await sOhm.initialize(staking.address, treasuryDeployment.address);

    // // TODO: different than deployAll.js (uses initialIndex instead of 0)
    // // doing this because the sohm contract has a require(index == 0)
    // // TODO: this is leading to a revert
    // // await sohmContract.setIndex(0);

    // await staking.setDistributor(distributor.address);

    // // Add staking contract a`s distributor recipient
    // await distributor.addRecipient(staking.address, INITIAL_REWARD_RATE);

    // // Approve staking contact to spend deployer's OHM
    // await ohm.approve(staking.address, LARGE_APPROVAL);

    // // Do we do this in a different way?
    // // queue and toggle reward manager
    // await treasury.queueTimelock("8", distributor.address, deployer);
    // // queue and toggle deployer reserve depositor
    // await treasury.queueTimelock("0", deployer, deployer);
    // // queue and toggle liquidity depositor
    // await treasury.queueTimelock("4", deployer, deployer);
}

main()
    .then(() => process.exit())
    .catch(error => {
        console.error(error);
        process.exit(1);
})