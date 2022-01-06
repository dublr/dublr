const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying from address: " + deployer.address);
  console.log("Account balance: " + (await deployer.getBalance()));
  
  const Dublr = await ethers.getContractFactory("Dublr");

  // mintPrice = 0.000005   => mintPrice_x1e9 == mintPrice * 1e9 == 5000
  // mintETHEquiv = 10000
  // mintETHWEIEquiv = mintETHEquiv * 1e18
  // initialMintDUBLRWEI = mintETHWEIEquiv / mintPrice
  // == 2000000000000000000000000000 DUBLR wei (2B DUBLR, 10k ETH equiv @ 0.000005 ETH per DUBLR)
  //const dublr = await Dublr.deploy(5000, 2000000000000000000000000000);

  //console.log("Token address:", dublr.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
