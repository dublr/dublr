const { ethers } = require("hardhat");

// Run with: npx hardhat run --network rinkeby scripts/deploy.js 

async function main() {
    const signer = new ethers.Wallet(process.env.WALLET_PRIVATE_KEY, ethers.provider);
    console.log("Deploying from address: " + signer.address);

    const Dublr = await ethers.getContractFactory("Dublr", signer);

    // mintPrice = 0.000005   => mintPrice_x1e9 == mintPrice * 1e9 == 5000
    // mintETHEquiv = 10000
    // mintETHWEIEquiv = mintETHEquiv * 1e18
    // initialMintDUBLRWEI = mintETHWEIEquiv / mintPrice
    // == 2000000000000000000000000000 DUBLR wei (2B DUBLR, 10k ETH equiv @ 0.000005 ETH per DUBLR)
    const balanceBefore = await signer.getBalance();
    // TODO: specify nonce = 0 so that all chains have the same contract addr?
    const dublr = await Dublr.deploy(5000, "2000000000000000000000000000");
    const balanceAfter = await signer.getBalance();
    const deploymentCost = balanceBefore.sub(balanceAfter);
    
    // Register Dublr DEX functions with Parity registry, since this is used by MetaMask
    // to look up function names: https://docs.metamask.io/guide/registering-function-names.html
    const PARITY_REGISTRY_ADDR = "0x44691B39d1a75dC4E0A0346CBB15E310e6ED1E86";
    const PARITY_ABI = ["function register(string memory method) external"];
    const parityContract = new ethers.Contract(PARITY_REGISTRY_ADDR, PARITY_ABI, signer);
    try {
        await parityContract.register("buy(uint256,bool,bool)");
        await parityContract.register("sell(uint256,uint256)");
        await parityContract.register("cancelMySellOrder()");
    } catch (e) {
        console.log("Could not register methods in Parity registry:", e.message);
    }

    console.log("Token address:", dublr.address);
    console.log("Deployment cost: " + ethers.utils.formatEther(deploymentCost) + " ETH");
    console.log("Contract ABI:", dublr.interface.format(ethers.utils.FormatTypes.full));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
    console.error(error);
    process.exit(1);
    });
