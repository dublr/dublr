const hardhat = require("hardhat");
const { ethers } = require("hardhat");

// Run with: npx hardhat run --network maticmum scripts/deploy.js 

// Note: deployment should be the first thing that is done with the deploying wallet
// on every chain, so that nonce = 0 on deployment to each chain, so that the contract
// gets the same address on all chains.

// N.B. public interface (buy, sell, and cancelMySellOrder) should be registered with
// https://www.4byte.directory/ in order for MetaMask to show the name of the non-view
// functions called.

async function runPromise(promise) {
    try {
        return await promise;
    } catch (e) {
        console.log(e.message);
        throw e;
    }
}

async function main() {
    const signer = new ethers.Wallet(hardhat.network.config.account, ethers.provider);
    console.log("Deploying from owner wallet: " + signer.address);
    const balanceBefore = await runPromise(signer.getBalance());

    console.log("Creating contract");
    const Dublr = await ethers.getContractFactory("Dublr", signer);

    // Don't deploy with any tokens assigned to owner:
    // https://www.sec.gov/corpfin/framework-investment-contract-analysis-digital-assets
    // There may be a reasonable expectation of profits (making the deployed token a security)
    // if "The AP [Active Participant] is able to benefit from its efforts as a result of
    // holding the same class of digital assets as those being distributed to the public."
    console.log("Deploying contract");
    const dublr = await runPromise(Dublr.deploy(500000, 0, {gasLimit: 2e7}));

    const balanceAfter = await runPromise(signer.getBalance());
    const deploymentCost = balanceBefore.sub(balanceAfter);

    console.log("Contract deployed to address:", dublr.address);
    console.log("Deployment cost: " + ethers.utils.formatEther(deploymentCost));
    console.log("Contract ABI (use to update dapp):");
    console.log(dublr.interface.format(ethers.utils.FormatTypes.full));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
