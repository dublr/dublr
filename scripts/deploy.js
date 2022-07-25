const { ethers } = require("hardhat");

// Run with: npx hardhat run --network rinkeby scripts/deploy.js 

async function main() {
  const signer = new ethers.Wallet(process.env.RINKEBY_PRIVATE_KEY, ethers.provider);
  console.log("Deploying from address: " + signer.address);
  console.log("Account balance: " + (await signer.getBalance()));
  
  const Dublr = await ethers.getContractFactory("Dublr", signer);

  // mintPrice = 0.000005   => mintPrice_x1e9 == mintPrice * 1e9 == 5000
  // mintETHEquiv = 10000
  // mintETHWEIEquiv = mintETHEquiv * 1e18
  // initialMintDUBLRWEI = mintETHWEIEquiv / mintPrice
  // == 2000000000000000000000000000 DUBLR wei (2B DUBLR, 10k ETH equiv @ 0.000005 ETH per DUBLR)
  const dublr = await Dublr.deploy(5000, "2000000000000000000000000000");

  console.log("Token address:", dublr.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
