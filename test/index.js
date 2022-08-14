const { expect, use } = require("chai");
const { ethers } = require("hardhat");
const { signERC2612Permit } = require("eth-permit");
const { BigNumber } = require("@ethersproject/bignumber");

const { ensureERC1820RegistryDeployed } = require("./ERC1820.js");

const ERC777Recipient = require("../artifacts/contracts/test/ERC777Recipient.sol/ERC777Recipient.json");
const ERC777Sender = require("../artifacts/contracts/test/ERC777Sender.sol/ERC777Sender.json");
const ERC1363Spender = require("../artifacts/contracts/test/ERC1363Spender.sol/ERC1363Spender.json");
const ERC1363Receiver = require("../artifacts/contracts/test/ERC1363Receiver.sol/ERC1363Receiver.json");
const ERC4524Recipient = require("../artifacts/contracts/test/ERC4524Recipient.sol/ERC4524Recipient.json");
const UnpayableBuyer = require("../artifacts/contracts/test/UnpayableBuyer.sol/UnpayableBuyer.json");
const UnpayableSeller = require("../artifacts/contracts/test/UnpayableSeller.sol/UnpayableSeller.json");

async function deployContract(wallet, contract, constructorArgs) {
    const contractInstance = await ethers.ContractFactory.fromSolidity(contract, wallet)
            .deploy(...constructorArgs);
    await contractInstance.deployed();
    return contractInstance;
}

describe("OmniToken", () => {
  let wallet;
  let Dublr;
  let contract0;
  let contractERC1820Registry;
  const initialSupply = 1000;

  beforeEach(async () => {
    wallet = await ethers.getSigners();
    contractERC1820Registry = await ensureERC1820RegistryDeployed(ethers.provider, wallet[9]);
    Dublr = await ethers.getContractFactory("Dublr");
    contract0 = await Dublr.deploy(5000, initialSupply);
    await contract0.deployed();
  });

  // Test ERC-20 interface

  it("ERC20: Constant functions", async () => {
    expect(await contract0.name()).to.equal("Dublr");
    expect(await contract0.symbol()).to.equal("DUBLR");
    expect(await contract0.version()).to.equal("1");
    expect(await contract0.decimals()).to.equal(18);
    expect(await contract0.granularity()).to.equal(1);
    const ierc20InterfaceId = 0x36372b07;
    expect(await contract0.supportsInterface(ierc20InterfaceId)).to.equal(true);
  });

  it("ERC20: totalSupply", async () => {
    expect(await contract0.totalSupply()).to.equal(1000);
  });

  it("ERC20: balanceOf", async () => {
    expect(await contract0.balanceOf(wallet[0].address)).to.equal(1000);
  });

  it("ERC20: Transfer adds amount to recipient and subtracts from sender", async () => {
    await contract0["transfer(address,uint256)"](wallet[1].address, 7);
    expect(await contract0.balanceOf(wallet[1].address)).to.equal(7);
    expect(await contract0.balanceOf(wallet[0].address)).to.equal(993);
  });

  it("ERC20: enableTransferToContracts", async () => {
    await contract0._owner_enableTransferToContracts(false);
    await expect(contract0["transfer(address,uint256)"](contractERC1820Registry.address, 7))
            .to.be.revertedWith("Can't transfer to a contract");
    await contract0._owner_enableTransferToContracts(true);
    await contract0["transfer(address,uint256)"](contractERC1820Registry.address, 7);
  });

  it("ERC20: Can transfer full balance", async () => {
    await contract0["transfer(address,uint256)"](wallet[1].address, 1000);
    expect(await contract0.balanceOf(wallet[1].address)).to.equal(1000);
    expect(await contract0.balanceOf(wallet[0].address)).to.equal(0);
  });
  
  it("ERC20: Cannot transfer more than balance", async () => {
    // .to.be.revertedWith requires "await expect()" not "expect(await",
    // otherwise revert is not caught by Chai
    await expect(contract0["transfer(address,uint256)"](wallet[1].address, 1001))
            .to.be.revertedWith("Insufficient balance");
  });
  
  it("ERC20: Test disabling API", async () => {
    await contract0._owner_enableERC20(false);
    await expect(contract0["transfer(address,uint256)"](wallet[1].address, 1000))
            .to.be.revertedWith("Disabled");
    await contract0._owner_enableERC20(true);
    await contract0["transfer(address,uint256)"](wallet[1].address, 1000);
  });

  it("ERC20: Cannot transfer from empty account", async () => {
    // New copy of contract, but connected to the contract as wallet[1] rather than wallet[0]
    const contract1 = await contract0.connect(wallet[1]);
    await expect(contract1["transfer(address,uint256)"](wallet[0].address, 1))
            .to.be.revertedWith("Insufficient balance");
  });

  it("ERC20: Transfer emits event", async () => {
    expect(await contract0["transfer(address,uint256)"](wallet[1].address, 7))
      .to.emit(contract0, "Transfer")
      .withArgs(wallet[0].address, wallet[1].address, 7);
  });

  it("ERC20: Set allowance and send to own wallet", async () => {
    await contract0["approve(address,uint256)"](wallet[1].address, 100);
    expect(await contract0["allowance(address,address)"](wallet[0].address, wallet[1].address))
            .to.equal(100);
    await contract0._owner_enableChangingAllowanceWithoutZeroing(false);
    await expect(contract0["approve(address,uint256)"](wallet[1].address, 150))
            .to.be.revertedWith("Curr allowance nonzero");
    const contract1 = await contract0.connect(wallet[1]);
    expect(await contract1.allowance(wallet[0].address, wallet[1].address)).to.equal(100);
    await contract1.transferFrom(wallet[0].address, wallet[1].address, 100);
    expect(await contract1.allowance(wallet[0].address, wallet[1].address)).to.equal(0);
    expect(await contract1.balanceOf(wallet[0].address)).to.equal(900);
    expect(await contract1.balanceOf(wallet[1].address)).to.equal(100);
    expect(await contract1.balanceOf(wallet[2].address)).to.equal(0);
    await expect(contract1.transferFrom(wallet[0].address, wallet[1].address, 100))
            .to.be.revertedWith("Insufficient allowance");
    await contract0._owner_enableChangingAllowanceWithoutZeroing(true);
    await contract0["approve(address,uint256)"](wallet[1].address, 150);
  });

  it("ERC20: Set allowance and send to other wallet", async () => {
    await contract0["approve(address,uint256)"](wallet[1].address, 100);
    const contract1 = await contract0.connect(wallet[1]);
    expect(await contract1.allowance(wallet[0].address, wallet[1].address)).to.equal(100);
    await contract1.transferFrom(wallet[0].address, wallet[2].address, 100);
    expect(await contract1.allowance(wallet[0].address, wallet[1].address)).to.equal(0);
    expect(await contract1.balanceOf(wallet[0].address)).to.equal(900);
    expect(await contract1.balanceOf(wallet[1].address)).to.equal(0);
    expect(await contract1.balanceOf(wallet[2].address)).to.equal(100);
    await expect(contract1.transferFrom(wallet[0].address, wallet[2].address, 100))
            .to.be.revertedWith("Insufficient allowance");
  });

  it("ERC20: Cannot transferFrom without allowance", async () => {
    const contract1 = await contract0.connect(wallet[1]);
    await expect(contract1.transferFrom(wallet[0].address, wallet[1].address, 100))
            .to.be.revertedWith("Insufficient allowance");
  });

  it("ERC20: Unlimited allowance", async () => {
    const contract1 = await contract0.connect(wallet[1]);
    const unlimited = ethers.constants.MaxUint256;
    await contract0._owner_enableUnlimitedAllowances(false);
    await expect(contract0["approve(address,uint256)"](wallet[1].address, unlimited))
            .to.be.revertedWith("Unlimited allowance disabled");
    await expect(contract1._owner_enableUnlimitedAllowances(true)).to.be.revertedWith("Not owner");
    await contract0._owner_enableUnlimitedAllowances(true);
    await contract0["approve(address,uint256)"](wallet[1].address, unlimited);
    expect(await contract0.allowance(wallet[0].address, wallet[1].address)).to.equal(unlimited);
    expect(await contract1.allowance(wallet[0].address, wallet[1].address)).to.equal(unlimited);
    await contract1.transferFrom(wallet[0].address, wallet[1].address, 100);
    expect(await contract1.allowance(wallet[0].address, wallet[1].address)).to.equal(unlimited);
    expect(await contract1.balanceOf(wallet[0].address)).to.equal(900);
    expect(await contract1.balanceOf(wallet[1].address)).to.equal(100);
    await expect(contract0.increaseAllowance(wallet[1].address, 100))
            .to.be.revertedWith("Unlimited allowance");
    await expect(contract0.decreaseAllowance(wallet[1].address, 100))
            .to.be.revertedWith("Unlimited allowance");
    await contract0._owner_enableUnlimitedAllowances(true);
    await contract0["approve(address,uint256)"](wallet[1].address, unlimited);
  });

  it("ERC20 extension: increaseAllowance / decreaseAllowance", async () => {
    await contract0["approve(address,uint256)"](wallet[1].address, 100);
    await contract0.increaseAllowance(wallet[1].address, 50);
    expect(await contract0.allowance(wallet[0].address, wallet[1].address)).to.equal(150);
    await contract0.decreaseAllowance(wallet[1].address, 100);
    expect(await contract0.allowance(wallet[0].address, wallet[1].address)).to.equal(50);
    await expect(contract0.decreaseAllowance(wallet[1].address, 100))
            .to.be.revertedWith("Insufficient allowance");
  });

  it("ERC20 extension: set allowance with expected current value", async () => {
    const contract1 = await contract0.connect(wallet[1]);
    await expect(contract0["approve(address,uint256,uint256)"](wallet[1].address, 1, 100))
            .to.be.revertedWith("Allowance mismatch");
    await contract0["approve(address,uint256,uint256)"](wallet[1].address, 0, 100);
    expect(await contract0.allowance(wallet[0].address, wallet[1].address)).to.equal(100);
    await expect(contract0["approve(address,uint256,uint256)"](wallet[1].address, 0, 100))
            .to.be.revertedWith("Allowance mismatch");
    expect(await contract0.allowance(wallet[0].address, wallet[1].address)).to.equal(100);
    await contract1.transferFrom(wallet[0].address, wallet[2].address, 50);
    expect(await contract0.allowance(wallet[0].address, wallet[1].address)).to.equal(50);
    await expect(contract0["approve(address,uint256,uint256)"](wallet[1].address, 0, 100))
            .to.be.revertedWith("Allowance mismatch");
    await expect(contract0["approve(address,uint256,uint256)"](wallet[1].address, 100, 100))
            .to.be.revertedWith("Allowance mismatch");
    await contract0["approve(address,uint256,uint256)"](wallet[1].address, 50, 0);
    expect(await contract0.allowance(wallet[0].address, wallet[1].address)).to.equal(0);
  });

  it("ERC20 extension: allowanceWithExpiration", async () => {
    const contract1 = await contract0.connect(wallet[1]);
    const block = await ethers.provider.getBlock(await ethers.provider.getBlockNumber());
    const timeBefore = block.timestamp;
    await contract0._owner_setDefaultAllowanceExpirationSec(3600);
    await contract0["approve(address,uint256,uint256)"](wallet[1].address, 0, 100);
    const expInfo0 = await contract0.allowanceWithExpiration(wallet[0].address, wallet[1].address);
    // Default allowance expiry time is 3600 sec
    expect(expInfo0.expirationTimestamp - timeBefore).to.be.closeTo(3600, 2);
    await contract1.transferFrom(wallet[0].address, wallet[2].address, 50);
    // Advance (3600 - 10) seconds
    await ethers.provider.send("evm_increaseTime", [3600 - 10]);
    await ethers.provider.send("evm_mine");
    await contract1.transferFrom(wallet[0].address, wallet[2].address, 25); // Should still succeed
    // Advance 15 seconds
    await ethers.provider.send("evm_increaseTime", [15]);
    await expect(contract1.transferFrom(wallet[0].address, wallet[2].address, 25))
            .to.be.revertedWith("Allowance expired");
    await ethers.provider.send("evm_mine");
    // Unlimited approval expiration
    await contract0["approveWithExpiration(address,uint256,uint256)"](wallet[1].address, 100,
            ethers.constants.MaxUint256);
    await contract1.transferFrom(wallet[0].address, wallet[2].address, 50);
    const expInfo1 = await contract0.allowanceWithExpiration(wallet[0].address, wallet[1].address);
    expect(expInfo1.remainingAmount).to.equal(50);
    expect(expInfo1.expirationTimestamp).to.equal(ethers.constants.MaxUint256);
    await expect(contract1.transferFrom(wallet[0].address, wallet[2].address, 51))
            .to.be.revertedWith("Insufficient allowance");
  });

  it("ERC20 extension: burn", async () => {
    await contract0["burn(uint256)"](90);
    expect(await contract0.balanceOf(wallet[0].address)).to.equal(910);
    await expect(contract0["burn(uint256)"](1000)).to.be.revertedWith("Insufficient balance");
  });
  
  // Test ERC-777 interface
  
  it("ERC777: send function should revert for non-ERC777 contract recipient", async () => {
    const contractERC1363Receiver = await deployContract(wallet[1], ERC1363Receiver, []);
    await expect(contract0["send(address,uint256,bytes)"](contractERC1363Receiver.address, 200, []))
            .to.be.revertedWith("Not ERC777 recipient");
  });
  
  it("ERC777: send function should succeed for EOA recipient", async () => {
    await contract0["send(address,uint256,bytes)"](wallet[1].address, 200, []);
    expect(await contract0.balanceOf(wallet[1].address)).to.equal(200);
    expect(await contract0.balanceOf(wallet[0].address)).to.equal(800);
  });
  
  it("ERC777: send function should call ERC777 recipient, with non-ERC777 sender", async () => {
    const contractERC777Recipient = await deployContract(wallet[1], ERC777Recipient, []);
    expect(await contractERC777Recipient.callCount()).to.equal(0);
    await contract0["send(address,uint256,bytes)"](contractERC777Recipient.address, 200, []);
    expect(await contractERC777Recipient.callCount()).to.equal(1);
    expect(await contract0.balanceOf(contractERC777Recipient.address)).to.equal(200);
    expect(await contract0.balanceOf(wallet[0].address)).to.equal(800);
  });
  
  it("ERC777: send function should call ERC777 sender interface if present", async () => {
    const contract9 = await contract0.connect(wallet[9]);
    await contract0["transfer(address,uint256)"](wallet[9].address, 1000);
    const contractERC777Recipient = await deployContract(wallet[1], ERC777Recipient, []);
    const contractERC777Sender = await deployContract(wallet[8], ERC777Sender, [wallet[9].address]);
    await contractERC1820Registry["setInterfaceImplementer(address,bytes32,address)"](
            wallet[9].address,
            ethers.utils.keccak256(ethers.utils.toUtf8Bytes("ERC777TokensSender")),
            contractERC777Sender.address);
    expect(await contractERC777Sender.callCount()).to.equal(0);
    await contract9["send(address,uint256,bytes)"](contractERC777Recipient.address, 200, []);
    expect(await contractERC777Sender.callCount()).to.equal(1);
    expect(await contract0.balanceOf(contractERC777Recipient.address)).to.equal(200);
    expect(await contract0.balanceOf(wallet[9].address)).to.equal(800);
    expect(await contract0.balanceOf(contractERC777Sender.address)).to.equal(0);
  });
  
  it("ERC777: test reentrancy protection", async () => {
    const contractERC777Recipient = await deployContract(wallet[1], ERC777Recipient, []);
    // Test that sending succeeds, then entable a reentrant call, then try the same send
    await contract0["send(address,uint256,bytes)"](contractERC777Recipient.address, 200, []);
    await contractERC777Recipient.testReentry(true);
    try {
      await contract0["send(address,uint256,bytes)"](contractERC777Recipient.address, 200, []);
      expect(true).to.equal(false);  // Fail if call succeeds
    } catch (error) {
      expect(error.message).to.contain("Reentrance");
    }
  });

  it("ERC777: burn", async () => {
    await contract0["burn(uint256,bytes)"](90, []);
    expect(await contract0.balanceOf(wallet[0].address)).to.equal(910);
    await expect(contract0["burn(uint256,bytes)"](1000, [])).to.be.revertedWith("Insufficient balance");
  });

  it("ERC777: authorizeOperator / revokeOperator", async () => {
    expect(await contract0.isOperatorFor(wallet[1].address, wallet[0].address)).to.equal(false);
    await contract0.authorizeOperator(wallet[1].address);
    expect(await contract0.isOperatorFor(wallet[1].address, wallet[0].address)).to.equal(true);
    await contract0.revokeOperator(wallet[1].address);
    expect(await contract0.isOperatorFor(wallet[1].address, wallet[0].address)).to.equal(false);
  });

  it("ERC777: operatorSend", async () => {
    const contract1 = await contract0.connect(wallet[1]);
    await expect(contract1.operatorSend(wallet[0].address, wallet[2].address, 200, [], []))
            .to.be.revertedWith("Not operator");
    await contract0.authorizeOperator(wallet[1].address);
    await contract1.operatorSend(wallet[0].address, wallet[2].address, 200, [], []);
    expect(await contract0.balanceOf(wallet[0].address)).to.equal(800);
    expect(await contract0.balanceOf(wallet[1].address)).to.equal(0);
    expect(await contract0.balanceOf(wallet[2].address)).to.equal(200);
    await contract0.revokeOperator(wallet[1].address);
    await expect(contract1.operatorSend(wallet[0].address, wallet[2].address, 200, [], []))
            .to.be.revertedWith("Not operator");
  });

  it("ERC777: operatorBurn", async () => {
    const contract1 = await contract0.connect(wallet[1]);
    await expect(contract1.operatorBurn(wallet[0].address, 200, [], []))
            .to.be.revertedWith("Not operator");
    await contract0.authorizeOperator(wallet[1].address);
    await contract1.operatorBurn(wallet[0].address, 200, [], []);
    expect(await contract0.balanceOf(wallet[0].address)).to.equal(800);
    expect(await contract0.balanceOf(wallet[1].address)).to.equal(0);
    await contract0.revokeOperator(wallet[1].address);
    await expect(contract1.operatorBurn(wallet[0].address, 200, [], []))
            .to.be.revertedWith("Not operator");
  });
  
  // Test ERC1363 interface
  
  it("ERC1363: transferAndCall", async () => {
    const contractERC1363Receiver = await deployContract(wallet[1], ERC1363Receiver, []);
    expect(await contractERC1363Receiver.callCount()).to.equal(0);
    await contract0["transferAndCall(address,uint256)"](contractERC1363Receiver.address, 100);
    expect(await contractERC1363Receiver.callCount()).to.equal(1);
    expect(await contract0.balanceOf(contractERC1363Receiver.address)).to.equal(100);
    expect(await contract0.balanceOf(wallet[0].address)).to.equal(900);
    await contractERC1363Receiver.enable(false);
    await expect(contract0["transferAndCall(address,uint256)"](contractERC1363Receiver.address, 100))
            .to.be.revertedWith("Not ERC1363 recipient");
  });

  it("ERC1363: transferFromAndCall", async () => {
    const contractERC1363Receiver = await deployContract(wallet[8], ERC1363Receiver, []);
    await contract0["approve(address,uint256)"](wallet[1].address, 100);
    const contract1 = await contract0.connect(wallet[1]);
    expect(await contract1.allowance(wallet[0].address, wallet[1].address)).to.equal(100);
    expect(await contractERC1363Receiver.callCount()).to.equal(0);
    await contract1["transferFromAndCall(address,address,uint256)"]
            (wallet[0].address, contractERC1363Receiver.address, 100);
    expect(await contractERC1363Receiver.callCount()).to.equal(1);
    expect(await contract1.allowance(wallet[0].address, wallet[1].address)).to.equal(0);
    expect(await contract1.balanceOf(wallet[0].address)).to.equal(900);
    expect(await contract1.balanceOf(wallet[1].address)).to.equal(0);
    expect(await contract1.balanceOf(contractERC1363Receiver.address)).to.equal(100);
    await expect(contract1["transferFromAndCall(address,address,uint256)"]
            (wallet[0].address, contractERC1363Receiver.address, 100))
                    .to.be.revertedWith("Insufficient allowance");
  });
  
  it("ERC1363: transferFromAndCall to EOA should fail", async () => {
    const contract1 = await contract0.connect(wallet[1]);
    await expect(contract1["transferFromAndCall(address,address,uint256)"]
            (wallet[0].address, wallet[2].address, 100))
                    .to.be.revertedWith("Insufficient allowance");
    await contract0["approve(address,uint256)"](wallet[1].address, 100);
    await expect(contract1["transferFromAndCall(address,address,uint256)"]
            (wallet[0].address, wallet[2].address, 100))
                    // Can't send to EOA with ERC1363
                    .to.be.revertedWith("Not ERC1363 recipient");
  });
  
  it("ERC1363: approveFromAndCall", async () => {
    const contractERC1363Spender = await deployContract(wallet[8], ERC1363Spender, []);
    expect(await contractERC1363Spender.callCount()).to.equal(0);
    await contract0["approveAndCall(address,uint256)"](contractERC1363Spender.address, 100);
    expect(await contractERC1363Spender.callCount()).to.equal(1);
    await contractERC1363Spender["send(address,address,address,uint256)"]
            (contract0.address, wallet[0].address, wallet[1].address, 100);
    expect(await contract0.balanceOf(wallet[0].address)).to.equal(900);
    expect(await contract0.balanceOf(wallet[1].address)).to.equal(100);
    expect(await contract0.balanceOf(wallet[8].address)).to.equal(0);
  });

  // Test ERC4524 interface
  
  it("ERC4524: safeTransfer", async () => {
    const contractERC4524Recipient = await deployContract(wallet[8], ERC4524Recipient, []);
    expect(await contractERC4524Recipient.callCount()).to.equal(0);
    await contract0["safeTransfer(address,uint256)"](contractERC4524Recipient.address, 100);
    expect(await contractERC4524Recipient.callCount()).to.equal(1);
    expect(await contract0.balanceOf(contractERC4524Recipient.address)).to.equal(100);
    expect(await contract0.balanceOf(wallet[0].address)).to.equal(900);
    await contractERC4524Recipient.enable(false);
    await expect(contract0["safeTransfer(address,uint256)"](contractERC4524Recipient.address, 100))
            .to.be.revertedWith("Not ERC4524 recipient");
  });

  it("ERC4524: safeTransferFrom", async () => {
    const contractERC4524Recipient = await deployContract(wallet[8], ERC4524Recipient, []);
    await contract0["approve(address,uint256)"](wallet[1].address, 100);
    const contract1 = await contract0.connect(wallet[1]);
    expect(await contract1.allowance(wallet[0].address, wallet[1].address)).to.equal(100);
    expect(await contractERC4524Recipient.callCount()).to.equal(0);
    await contract1["safeTransferFrom(address,address,uint256)"]
            (wallet[0].address, contractERC4524Recipient.address, 100);
    expect(await contractERC4524Recipient.callCount()).to.equal(1);
    expect(await contract1.allowance(wallet[0].address, wallet[1].address)).to.equal(0);
    expect(await contract1.balanceOf(wallet[0].address)).to.equal(900);
    expect(await contract1.balanceOf(wallet[1].address)).to.equal(0);
    expect(await contract1.balanceOf(contractERC4524Recipient.address)).to.equal(100);
    await expect(contract1["safeTransferFrom(address,address,uint256)"]
            (wallet[0].address, contractERC4524Recipient.address, 100))
                    .to.be.revertedWith("Insufficient allowance");
  });
  
  it("ERC4524: safeTransferFrom to EOA should succeed", async () => {
    const contract1 = await contract0.connect(wallet[1]);
    await expect(contract1["safeTransferFrom(address,address,uint256)"]
            (wallet[0].address, wallet[2].address, 100))
                    .to.be.revertedWith("Insufficient allowance");
    await contract0["approve(address,uint256)"](wallet[1].address, 100);
    await contract1["safeTransferFrom(address,address,uint256)"]
            (wallet[0].address, wallet[2].address, 100);
    expect(await contract0.balanceOf(wallet[0].address)).to.equal(900);
    expect(await contract0.balanceOf(wallet[1].address)).to.equal(0);
    expect(await contract0.balanceOf(wallet[2].address)).to.equal(100);
  });

  // Test permit APIs

  it("EIP2612: permit", async () => {
    expect(await contract0.allowance(wallet[0].address, wallet[1].address)).to.equal(0);
    const sig0 = await signERC2612Permit(/* wallet */ wallet[0], /* tokenAddress */ contract0.address,
            /* senderAddress */ wallet[0].address, /* spender */ wallet[1].address, /* allowedAmount */ 200);
    await contract0["permit(address,address,uint256,uint256,uint8,bytes32,bytes32)"](
            /* holder */ wallet[0].address, /* spender */ wallet[1].address, /* allowedAmount */ 200,
            /* deadline */ sig0.deadline, sig0.v, sig0.r, sig0.s);
    expect(await contract0.allowance(wallet[0].address, wallet[1].address)).to.equal(200);
    const contract1 = await contract0.connect(wallet[1]);
    await contract1.transferFrom(wallet[0].address, wallet[1].address, 100);
    expect(await contract0.allowance(wallet[0].address, wallet[1].address)).to.equal(100);
    expect(await contract0.balanceOf(wallet[0].address)).to.equal(900);
    expect(await contract0.balanceOf(wallet[1].address)).to.equal(100);
    // Have to re-sign for each new call to permit() since the nonce increments each time
    const sig1 = await signERC2612Permit(/* wallet */ wallet[0], /* tokenAddress */ contract0.address,
            /* senderAddress */ wallet[0].address, /* spender */ wallet[1].address, /* allowedAmount */ 200);
    await expect(contract0["permit(address,address,uint256,uint256,uint8,bytes32,bytes32)"](
            /* holder */ wallet[0].address, /* spender */ wallet[1].address, /* allowedAmount */ 200,
            /* deadline */ 1, sig1.v, sig1.r, sig1.s)).to.be.revertedWith("Expired"); 
    expect(await contract0.allowance(wallet[0].address, wallet[1].address)).to.equal(100);
    const sig2 = await signERC2612Permit(/* wallet */ wallet[0], /* tokenAddress */ contract0.address,
            /* senderAddress */ wallet[0].address, /* spender */ wallet[1].address, /* allowedAmount */ 0);
    await contract0["permit(address,address,uint256,uint256,uint8,bytes32,bytes32)"](
            /* holder */ wallet[0].address, /* spender */ wallet[1].address, /* allowedAmount */ 0,
            /* deadline */ sig2.deadline, sig2.v, sig2.r, sig2.s); 
    expect(await contract0.allowance(wallet[0].address, wallet[1].address)).to.equal(0);
    const sig3 = await signERC2612Permit(/* wallet */ wallet[0], /* tokenAddress */ contract0.address,
            /* senderAddress */ wallet[0].address, /* spender */ wallet[1].address, /* allowedAmount */ 1);
    await expect(contract0["permit(address,address,uint256,uint256,uint8,bytes32,bytes32)"](
            /* holder */ wallet[0].address, /* spender */ wallet[1].address, /* allowedAmount */ 0,
            /* deadline */ sig3.deadline, sig3.v, sig3.r, sig3.s))
                    .to.be.revertedWith("Bad sig"); // wrong allowedAmount
    const invalidVal0 = '0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe';
    const invalidVal1 = '0x7effffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
    await expect(contract0["permit(address,address,uint256,uint256,uint8,bytes32,bytes32)"](
            /* holder */ wallet[0].address, /* spender */ wallet[1].address, /* allowedAmount */ 1,
            /* deadline */ invalidVal0, sig3.v, sig3.r, sig3.s))
                    .to.be.revertedWith("Bad sig"); // wrong deadline
    await expect(contract0["permit(address,address,uint256,uint256,uint8,bytes32,bytes32)"](
            /* holder */ wallet[0].address, /* spender */ wallet[1].address, /* allowedAmount */ 1,
            /* deadline */ sig3.deadline, 1, sig3.r, sig3.s))
                    .to.be.revertedWith("Bad sig"); // wrong v val (must be 27 or 28)
    await expect(contract0["permit(address,address,uint256,uint256,uint8,bytes32,bytes32)"](
            /* holder */ wallet[0].address, /* spender */ wallet[1].address, /* allowedAmount */ 1,
            /* deadline */ sig3.deadline, sig3.v, invalidVal0, sig3.s))
                    .to.be.revertedWith("Bad sig"); // wrong r
    await expect(contract0["permit(address,address,uint256,uint256,uint8,bytes32,bytes32)"](
            /* holder */ wallet[0].address, /* spender */ wallet[1].address, /* allowedAmount */ 1,
            /* deadline */ sig3.deadline, sig3.v, sig3.r, invalidVal0))
                    .to.be.revertedWith("Bad sig"); // s too large
    await expect(contract0["permit(address,address,uint256,uint256,uint8,bytes32,bytes32)"](
            /* holder */ wallet[0].address, /* spender */ wallet[1].address, /* allowedAmount */ 1,
            /* deadline */ sig3.deadline, sig3.v, sig3.r, invalidVal1))
                    .to.be.revertedWith("Bad sig"); // wrong s
  });

  it("Multichain: needs authorized router", async () => {
    await expect(contract0["mint(address,uint256)"](wallet[0].address, 1000))
            .to.be.revertedWith("Not authorized");
    await contract0._owner_authorizeMultichainRouter(wallet[0].address, true);
    await contract0["mint(address,uint256)"](wallet[0].address, 1000);
    expect(await contract0.balanceOf(wallet[0].address)).to.equal(2000);
    await contract0._owner_authorizeMultichainRouter(wallet[0].address, false);
    await expect(contract0["mint(address,uint256)"](wallet[0].address, 1000))
            .to.be.revertedWith("Not authorized");
    await contract0._owner_authorizeMultichainRouter(wallet[0].address, true);
    await contract0["mint(address,uint256)"](wallet[0].address, 1000);
    expect(await contract0.balanceOf(wallet[0].address)).to.equal(3000);
    await contract0._owner_enableMultichainRouting(false);
    await expect(contract0["mint(address,uint256)"](wallet[0].address, 1000))
            .to.be.revertedWith("Not authorized");
    expect(await contract0.balanceOf(wallet[0].address)).to.equal(3000);
  });

});

describe("Dublr", () => {
  let wallet;
  let Dublr;
  let contract0;

  // Tokens are 1c each if ETH/USD price is $2k:
  // (USD/DUBLR) = (2000 USD/ETH) * (5000 * 10^-9 ETH/DUBLR) = 0.01
  const initialMintPriceETHPerDUBLR_x1e9 = 5000;
  const initialSupply = 1000;
  const DOUBLING_PERIOD_DAYS = 90;
  
  function toETH(dublrAmt) { return Math.trunc(dublrAmt * initialMintPriceETHPerDUBLR_x1e9 / 1e9); }
  function toDUBLR(ethAmt) { return Math.trunc(ethAmt * 1e9 / initialMintPriceETHPerDUBLR_x1e9); }

  beforeEach(async () => {
    wallet = await ethers.getSigners();
    Dublr = await ethers.getContractFactory("Dublr");
    contract0 = await Dublr.deploy(initialMintPriceETHPerDUBLR_x1e9, initialSupply);
    await contract0.deployed();
  });

  // Test Dublr-specific API

  it("Minting can be disabled, but by owner only", async () => {
    const contract1 = contract0.connect(wallet[1]);
    await expect(contract1._owner_enableBuying(true)).to.be.revertedWith("Not owner");
    await expect(contract1._owner_enableMinting(true)).to.be.revertedWith("Not owner");
    await contract0._owner_enableBuying(false);
    await contract0._owner_enableMinting(false);
    await contract1["buy(uint256,bool,bool)"](0, true, true, {value: 10});
    expect(await contract0.balanceOf(wallet[1].address)).to.equal(0);
    await contract0._owner_enableMinting(true);
    await contract1["buy(uint256,bool,bool)"](0, true, true, {value: 10});
    expect(await contract0.balanceOf(wallet[1].address)).to.equal(10 * 1e9 / initialMintPriceETHPerDUBLR_x1e9);
  });
    
  it("Mint price", async () => {
    await ethers.provider.send("evm_mine");
    const contractBlockTimestamp = (await ethers.provider.getBlock(
            contract0.deployTransaction.blockNumber)).timestamp;
    expect(await contract0.mintPrice()).to.equal(initialMintPriceETHPerDUBLR_x1e9);
    var prevMintPrice = initialMintPriceETHPerDUBLR_x1e9;
    // Mint price doubles for 30 doubling periods
    for (var i = 0; i < 30; i++) {
      const t = (i + 1) * (3600 * 24 * DOUBLING_PERIOD_DAYS);
      const timestamp = contractBlockTimestamp + t;
      await ethers.provider.send("evm_setNextBlockTimestamp", [timestamp]);
      await ethers.provider.send("evm_mine");
      const mintPrice = await contract0.mintPrice();
      // console.log((i + 1) * 90 + " " + mintPrice * 1.0e-9);
      const mintPriceRatio = mintPrice / prevMintPrice;
      // Ratio after 1st doubling period: 1.999528
      // Ratio after 30th doubling period: 1.973042
      expect(mintPriceRatio).to.be.closeTo(2.0, 0.03);
      prevMintPrice = mintPrice;
    }
    // Mint price is 0 thereafter (minting is disabled after this time)
    for (var i = 0; i < 5; i++) {
      await ethers.provider.send("evm_increaseTime", [3600 * 24]);
      await ethers.provider.send("evm_mine");
      expect(await contract0.mintPrice()).to.equal(0);
    }
  });

  it("Minting without any sell orders", async () => {
    await contract0._owner_setMinSellOrderValueETHWEI(0);
    const contract1 = await contract0.connect(wallet[1]);
    await expect(contract1["buy(uint256,bool,bool)"](0, true, true, )).to.be.revertedWith("Zero payment");
    await contract1["buy(uint256,bool,bool)"](0, true, true, {value: 1});
    const amt0 = toDUBLR(1);
    expect(await contract1.balanceOf(wallet[1].address)).to.equal(amt0);
    await contract1["buy(uint256,bool,bool)"](0, true, true, {value: 5});
    const amt1 = toDUBLR(5);
    expect(await contract1.balanceOf(wallet[1].address)).to.equal(amt0 + amt1);
    // Moving one doubling period forward should double the exchange rate, so buying with 1000000 ETH wei
    // should yield (1000000 wei / initialMintPriceETHPerDUBLR) = 500000 DUBLR wei tokens.
    await ethers.provider.send("evm_increaseTime", [3600 * 24 * DOUBLING_PERIOD_DAYS]);
    await ethers.provider.send("evm_mine");
    await contract1["buy(uint256,bool,bool)"](0, true, true, {value: 1000000});
    const amt2 = toDUBLR(1000000 / 2);
    // Need to do approximate comparison because exp function approximation is not perfect --
    // after DOUBLING_PERIOD_DAYS days, a price of 5000 grows to 9997, not to 10000
    expect((await contract1.balanceOf(wallet[1].address)) / (amt0 + amt1 + amt2)).to.be.closeTo(1.0, 0.03);
  });

  it("Only one sell order at once", async () => {
    await contract0._owner_setMinSellOrderValueETHWEI(0);
    expect(await contract0.orderBookSize()).to.equal(0);
    expect((await contract0.cheapestSellOrder()).amountDUBLRWEI).to.equal(0);  // No sell orders
    expect((await contract0.mySellOrder()).amountDUBLRWEI).to.equal(0);  // No sell order for caller
    await expect(contract0.sell(initialMintPriceETHPerDUBLR_x1e9 / 2, 1001))
            .to.be.revertedWith("Insufficient balance");
    const startBalance = await contract0.balanceOf(wallet[0].address);
    await contract0.sell(initialMintPriceETHPerDUBLR_x1e9 / 2, 100);
    expect(await contract0.orderBookSize()).to.equal(1);
    // balanceOf does not include the amount in an active sell order
    expect(await contract0.balanceOf(wallet[0].address)).to.equal(startBalance - 100);
    const order0 = await contract0.cheapestSellOrder();
    expect(order0.priceETHPerDUBLR_x1e9).to.equal(initialMintPriceETHPerDUBLR_x1e9 / 2);
    expect(order0.amountDUBLRWEI).to.equal(100);
    // Selling with an existing sell order should cancel the first sell order and replace it with the new one
    await contract0.sell(initialMintPriceETHPerDUBLR_x1e9 / 4, 200);
    expect(await contract0.orderBookSize()).to.equal(1);
    expect(await contract0.balanceOf(wallet[0].address)).to.equal(startBalance - 200);
    const order1 = await contract0.cheapestSellOrder();
    expect(order1.priceETHPerDUBLR_x1e9).to.equal(initialMintPriceETHPerDUBLR_x1e9 / 4);
    expect(order1.amountDUBLRWEI).to.equal(200);
    await contract0.cancelMySellOrder();
    expect(await contract0.orderBookSize()).to.equal(0);
    expect(await contract0.balanceOf(wallet[0].address)).to.equal(startBalance);
  });

  it("Sell orders are sorted", async () => {
    await contract0._owner_setMinSellOrderValueETHWEI(0);
    const contract1 = await contract0.connect(wallet[1]);
    const contract2 = await contract0.connect(wallet[2]);
    const contract3 = await contract0.connect(wallet[3]);
    const contract4 = await contract0.connect(wallet[4]);
    const contract5 = await contract0.connect(wallet[5]);
    await contract0["transfer(address,uint256)"](wallet[1].address, 10);
    await contract0["transfer(address,uint256)"](wallet[2].address, 10);
    await contract0["transfer(address,uint256)"](wallet[3].address, 10);
    await contract0["transfer(address,uint256)"](wallet[4].address, 10);
    await contract0["transfer(address,uint256)"](wallet[5].address, 10);

    await contract0.sell(40, 10);
    expect(await contract0.orderBookSize()).to.equal(1);
    expect((await contract0.cheapestSellOrder()).priceETHPerDUBLR_x1e9).to.equal(40);
    await contract1.sell(50, 10);
    expect(await contract0.orderBookSize()).to.equal(2);
    expect((await contract0.cheapestSellOrder()).priceETHPerDUBLR_x1e9).to.equal(40);
    await contract2.sell(30, 10);
    expect(await contract0.orderBookSize()).to.equal(3);
    expect((await contract0.cheapestSellOrder()).priceETHPerDUBLR_x1e9).to.equal(30);
    await contract3.sell(20, 10);
    expect(await contract0.orderBookSize()).to.equal(4);
    expect((await contract0.cheapestSellOrder()).priceETHPerDUBLR_x1e9).to.equal(20);
    await contract4.sell(60, 10);
    expect(await contract0.orderBookSize()).to.equal(5);
    expect((await contract0.cheapestSellOrder()).priceETHPerDUBLR_x1e9).to.equal(20);
    await contract5.sell(10, 10);
    expect(await contract0.orderBookSize()).to.equal(6);
    expect((await contract0.cheapestSellOrder()).priceETHPerDUBLR_x1e9).to.equal(10);
    
    // Check heap element order
    expect((await contract0.allSellOrders()).map(x => BigNumber.from(x[0]).toNumber()))
            .to.deep.equal([10, 30, 20, 50, 60, 40]);
    
    await contract5.cancelMySellOrder(); // 10
    expect(await contract0.orderBookSize()).to.equal(5);
    expect((await contract0.cheapestSellOrder()).priceETHPerDUBLR_x1e9).to.equal(20);
    await contract3.cancelMySellOrder(); // 20
    expect(await contract0.orderBookSize()).to.equal(4);
    expect((await contract0.cheapestSellOrder()).priceETHPerDUBLR_x1e9).to.equal(30);
    await contract3.sell(35, 10); // Insert new order at price 35
    expect(await contract0.orderBookSize()).to.equal(5);
    expect((await contract0.cheapestSellOrder()).priceETHPerDUBLR_x1e9).to.equal(30);
    await contract2.cancelMySellOrder(); // 30
    expect(await contract0.orderBookSize()).to.equal(4);
    expect((await contract0.cheapestSellOrder()).priceETHPerDUBLR_x1e9).to.equal(35);
    await contract3.cancelMySellOrder(); // 35
    expect(await contract0.orderBookSize()).to.equal(3);
    expect((await contract0.cheapestSellOrder()).priceETHPerDUBLR_x1e9).to.equal(40);
    await contract1.cancelMySellOrder(); // 50
    expect(await contract0.orderBookSize()).to.equal(2);
    expect((await contract0.cheapestSellOrder()).priceETHPerDUBLR_x1e9).to.equal(40);
    await contract0.cancelMySellOrder(); // 40
    expect(await contract0.orderBookSize()).to.equal(1);
    expect((await contract0.cheapestSellOrder()).priceETHPerDUBLR_x1e9).to.equal(60);
    await contract3.sell(70, 10); // Insert new order at price 70
    expect(await contract0.orderBookSize()).to.equal(2);
    expect((await contract0.cheapestSellOrder()).priceETHPerDUBLR_x1e9).to.equal(60);
    await contract3.cancelMySellOrder(); // 70
    expect(await contract0.orderBookSize()).to.equal(1);
    expect((await contract0.cheapestSellOrder()).priceETHPerDUBLR_x1e9).to.equal(60);
    await contract4.cancelMySellOrder(); // 60
    expect(await contract0.orderBookSize()).to.equal(0);
  });

  it("Sell orders can be bought", async () => {
    await contract0._owner_setMinSellOrderValueETHWEI(0);
    const contract1 = await contract0.connect(wallet[1]);
    const contract2 = await contract0.connect(wallet[2]);
    const contract3 = await contract0.connect(wallet[3]);
    
    // Mint coins for contract1 and contract2
    await contract1["buy(uint256,bool,bool)"](0, true, true, {value: 20, gasPrice: 0});  // 20 ETH wei => 4M DUBLR wei
    await contract2["buy(uint256,bool,bool)"](0, true, true, {value: 20, gasPrice: 0});
    expect(await contract0.balanceOf(wallet[1].address)).to.equal(4000000);

    await contract1.sell(initialMintPriceETHPerDUBLR_x1e9 / 2, 1200000);  // 400000 DUBL per ETH, 1200000 DUBLR = 3 ETH
    // Balance decreases when there is an active sell order
    expect(await contract0.balanceOf(wallet[1].address)).to.equal(2800000);
    await contract2.sell(initialMintPriceETHPerDUBLR_x1e9 / 4, 2400000); // 800000 DUBLR per ETH, 2400000 DUBLR = 3 ETH
    expect(await contract0.balanceOf(wallet[2].address)).to.equal(1600000);

    // Set gas price to 0 during transactions so that eth sent/received can be measured
    // (N.B. {gasPrice: 0} requires {initialBaseFeePerGas: 0} in hardhat.config.ts)
    const ethBalance0_0 = await wallet[0].getBalance();
    expect(await contract0.balanceOf(wallet[3].address, {gasPrice: 0})).to.equal(0);
    // Buy 2 ETH worth at wallet[2]'s order price of initialMintPriceETHPerDUBLR_x1e9 / 4 == 1250 * 10^-9.
    // => This translates to purchasing 2 * 10^9 / 1250 = 1600000 tokens.
    await contract3["buy(uint256,bool,bool)"](0, true, true, {value: 2, gasPrice: 0});
    expect(await contract0.balanceOf(wallet[3].address, {gasPrice: 0})).to.equal(1600000);
    // The tokens that were in wallet[2] but not part of the order should not have been sold
    expect(await contract0.balanceOf(wallet[2].address, {gasPrice: 0})).to.equal(1600000);
    const cheapestOrder = await contract0.cheapestSellOrder({gasPrice: 0});
    expect(cheapestOrder.priceETHPerDUBLR_x1e9).to.equal(initialMintPriceETHPerDUBLR_x1e9 / 4);
    expect(cheapestOrder.amountDUBLRWEI).to.equal(800000);
    // Canceling a sell order restores the sell order tokens back to the balance
    await contract1.cancelMySellOrder({gasPrice: 0});
    expect(await contract0.balanceOf(wallet[1].address, {gasPrice: 0})).to.equal(4000000);
    // Check holder (wallet[0]) receives fees.
    // 0 ETH wei fee, out of 2 ETH spent, because order is so small.
    const ethBalance0_1 = await wallet[0].getBalance();
    expect(ethBalance0_1.sub(ethBalance0_0)).to.equal(0);
    await contract2.cancelMySellOrder();
    expect(await contract0.balanceOf(wallet[2].address, {gasPrice: 0})).to.equal(2400000);
  });

  it("Larger sell orders", async () => {
    await contract0._owner_setMinSellOrderValueETHWEI(0);
    const contract1 = await contract0.connect(wallet[1]);
    const contract3 = await contract0.connect(wallet[3]);
    
    // Mint coins for contract1 and contract2
    await contract1["buy(uint256,bool,bool)"](0, true, true, {value: 100000, gasPrice: 0});  // 100000 ETH wei => 20B DUBLR wei
    expect(await contract0.balanceOf(wallet[1].address)).to.equal(2e10);

    await contract1.sell(initialMintPriceETHPerDUBLR_x1e9 / 2, 1e10);  // 1e10 DUBLR at 2500*10^-9 ETH per DUBLR
    
    const ethBalance0_1 = await wallet[0].getBalance();
    const ethBalance1_1 = await wallet[1].getBalance();
    await contract3["buy(uint256,bool,bool)"](0, true, true, {value: 10000, gasPrice: 0}); // Buy 10000 ETH
    expect((await contract0.cheapestSellOrder({gasPrice: 0})).priceETHPerDUBLR_x1e9)
            .to.equal(initialMintPriceETHPerDUBLR_x1e9 / 2);  // Price = 2500 still
    // Number of tokens purchased = 10000 * 1e9 / 2500 = 4000000000
    // Remaining in wallet[1]'s sell order = 1e10 - 4000000000 = 6000000000
    expect((await contract0.cheapestSellOrder({gasPrice: 0})).amountDUBLRWEI).to.equal(6000000000);
    const ethBalance0_2 = await wallet[0].getBalance();
    const ethBalance1_2 = await wallet[1].getBalance();
    // Check that fees are sent correctly to owner.
    // 10000 ETH was spent, so 10000 * 0.0015 = 15 ETH was collected as a market maker fee
    expect(ethBalance0_2.sub(ethBalance0_1)).to.equal(15);
    // Remainder is payment sent to seller
    expect(ethBalance1_2.sub(ethBalance1_1)).to.equal(10000 - 15);
  });

  it("Min sell value enforced", async () => {
    // Mint coins for contract0
    await contract0["buy(uint256,bool,bool)"](0, true, true, {value: 200000e9, gasPrice: 0});
    // Should fail if order amount is less than the minimum limit
    await expect(contract0.sell(1e9, "9999999999999999")).to.be.revertedWith("Order value too small");
    await contract0.sell(1e9, "10000000000000000");
  });

  it("Failure with out-of-gas condition", async () => {
    await contract0._owner_setMinSellOrderValueETHWEI(0);
    // Mint coins for contract0
    await contract0["buy(uint256,bool,bool)"](0, true, true, {value: "1000000000000000000", gasPrice: 0});
    
    const numWallets = 20;
    const amtPerWallet = 1e9 / initialMintPriceETHPerDUBLR_x1e9;  // 200000
    const wallets = [];
    const contracts = [];
    for (var i = 0; i < numWallets; i++) {  // Create a heap containing `i` orders
        // Create wallets[i] and fund it with amtPerWallet DUBLR
        const wallet_i = await ethers.Wallet.createRandom().connect(ethers.provider);
        await network.provider.send("hardhat_setBalance", [wallet_i.address, "0x100000000000000"]);
        wallets.push(wallet_i);
        await contract0["transfer(address,uint256)"](wallet_i.address, amtPerWallet);
        // Create a connection from wallets[i] to the new contract
        const contracti = await contract0.connect(wallet_i);
        contracts.push(contracti);
        // List the amtPerWallet tokens for each wallet on the exchange
        await contracti.sell(initialMintPriceETHPerDUBLR_x1e9, amtPerWallet);
    }    
    // Measure gas for buying the first sell order (value: 1 ETH).
    // This is an over-estimate of the gas consumption per sell order, because it includes all gas consumption
    // by the function
    const gasPerOrder = await contract0.estimateGas.buy(0, true, false, {value: 1});
    
    // Try buying a large amount, but only provide enough gas for buying a few orders.
    // Should terminate the buy early, reverting with "out of gas"
    await expect(contract0.buy(0, true, false, {value: 1e9, gasLimit: gasPerOrder * 3}))
            .to.be.reverted;
    // No orders were bought
    expect(await contract0.orderBookSize()).to.equal(numWallets);
  });

  it("Change given to buyer", async () => {
    dublr = await Dublr.deploy(100e9, 1);  // Re-deploy Dublr with 100 ETH == 1 DUBLR
    await dublr.deployed();
    await dublr._owner_setMinSellOrderValueETHWEI(0);

    const contract1 = await dublr.connect(wallet[1]);
    const contract2 = await dublr.connect(wallet[2]);
    // Mint coins for contract1
    await contract1["buy(uint256,bool,bool)"](0, true, true, {value: 1e9, gasPrice: 0});  // 1B ETH wei => 10M DUBLR wei
    expect(await dublr.balanceOf(wallet[1].address)).to.equal(10e6);

    await contract1.sell(50e9, 10e6);   // Sell at price 50 ETH == 1 DUBLR

    const ethBalance0_0 = await wallet[0].getBalance();
    const ethBalance1_0 = await wallet[1].getBalance();
    const ethBalance2_0 = await wallet[2].getBalance();
    // Buy with a value of 1000033 ETH
    // At 50 ETH per DUBLR, that buys 20000.66 DUBLR
    // 20k DUBLR should be bought for 1M ETH, and 33 ETH should be refunded to buyer.
    // Seller should receive 1M eth minus fee of .15% == 1M - 1500
    await contract2["buy(uint256,bool,bool)"](0, true, true, {value: 1000033, gasPrice: 0});
    expect(await dublr.balanceOf(wallet[2].address)).to.equal(20000);
    const ethBalance0_1 = await wallet[0].getBalance();
    const ethBalance1_1 = await wallet[1].getBalance();
    const ethBalance2_1 = await wallet[2].getBalance();
    expect(ethBalance0_1.sub(ethBalance0_0)).to.equal(1500);         // Fees sent to owner are 1500 ETH
    expect(ethBalance1_1.sub(ethBalance1_0)).to.equal(1e6 - 1500);   // Seller receives 1M ETH minus seller fee of 1500 ETH
    expect(ethBalance2_1.sub(ethBalance2_0)).to.equal(-1e6);         // Buyer spends 1000033 ETH, 33 ETH refunded
  });

  it("Roll over from one sell order to the next when an order is exhausted", async () => {
    await contract0._owner_setMinSellOrderValueETHWEI(0);
    const contract1 = await contract0.connect(wallet[1]);
    const contract2 = await contract0.connect(wallet[2]);
    const contract3 = await contract0.connect(wallet[3]);
    
    // Mint coins for contract1 and contract2
    await contract1["buy(uint256,bool,bool)"](0, true, true, {value: 100000, gasPrice: 0});  // 100000 ETH wei => 20B DUBLR wei
    await contract2["buy(uint256,bool,bool)"](0, true, true, {value: 100000, gasPrice: 0});
    expect(await contract0.balanceOf(wallet[1].address)).to.equal(2e10);

    await contract1.sell(initialMintPriceETHPerDUBLR_x1e9 / 4, 1e9);   // 1e9 DUBLR at 1250/1e9 ETH per DUBLR
    await contract2.sell(initialMintPriceETHPerDUBLR_x1e9 / 2, 1e10);  // 1e10 DUBLR at 2500/1e9 ETH per DUBLR
    
    const ethBalance0_0 = await wallet[0].getBalance();
    const ethBalance1_0 = await wallet[1].getBalance();
    const ethBalance2_0 = await wallet[2].getBalance();
    const ethBalance3_0 = await wallet[3].getBalance();
    // Buy all 1250 ETH worth of tokens from wallet[1], and 2000 ETH worth of tokens from wallet[2],
    // leaving 500ETH worth of tokens in wallet[2]'s order. In total, buyer sends 3250 ETH.
    // This purchases Math.trunc(3250 * 1e9 / 1250) == 2600000000 DUBLR.
    // The cheaper sell order only contains 1B DUBLR, so 1600000000 DUBLR must be purchased from the
    // more expensive sell order. The total amount of ETH spent on the first 1B tokens is
    // 1B DUBLR * (1250 / 1e9) = 1250 ETH.
    // Remaining is 3250 - 1250 = 2000 ETH.
    // The price of the more expensive order is 2500 * 10^-9 ETH per DUBLR.
    // The number of DUBLR tokens that can be bought with the remaining ETH balance is
    // 2000 / (2500 / 10^9) = 800000000.
    // Amount remaining of order = 1e10 - 800000000 == 9200000000
    // Fees collected on 3250 ETH = 3250 * .0015 = 4.875 ETH => rounded to 5 ETH
    await contract3["buy(uint256,bool,bool)"](0, true, true, {value: 3250, gasPrice: 0});
    // The cheapest order should have totally sold out, leaving only the more expensive order
    const cheapestSellOrder = await contract0.cheapestSellOrder({gasPrice: 0});
    expect(cheapestSellOrder.priceETHPerDUBLR_x1e9).to.equal(initialMintPriceETHPerDUBLR_x1e9 / 2);
    expect(cheapestSellOrder.amountDUBLRWEI).to.equal(9200000000);
    const ethBalance0_1 = await wallet[0].getBalance();
    const ethBalance1_1 = await wallet[1].getBalance();
    const ethBalance2_1 = await wallet[2].getBalance();
    const ethBalance3_1 = await wallet[3].getBalance();
    expect(ethBalance0_1.sub(ethBalance0_0)).to.equal(5);     // Owner fees
    expect(ethBalance1_1.sub(ethBalance1_0)).to.equal(1248);  // 1250 minus seller fee
    expect(ethBalance2_1.sub(ethBalance2_0)).to.equal(1997);  // 2000 minus seller fee
    expect(ethBalance3_1.sub(ethBalance3_0)).to.equal(-3250); // Buyer spent 3250, the original amount
  });  

  it("Buying transitions from buying sell orders to minting at mint price", async () => {
    await contract0._owner_setMinSellOrderValueETHWEI(0);
    const contract1 = await contract0.connect(wallet[1]);
    const contract2 = await contract0.connect(wallet[2]);

    await contract1["buy(uint256,bool,bool)"](0, true, true, {value: 100000, gasPrice: 0});  // 100000 ETH wei => 20B DUBLR wei

    await contract1.sell(2500, 2e10);  // 20B DUBLR at 2500/1e9 ETH per DUBLR (half the price they were bought at)

    const ethBalance0_0 = await wallet[0].getBalance();
    const ethBalance1_0 = await wallet[1].getBalance();
    const ethBalance2_0 = await wallet[2].getBalance();
    // Buy all 200000 ETH worth of DUBLR from wallet[1]'s sell order, then mint an extra 100000 ETH worth of DUBLR.
    const amtSpent = 300000;
    await contract2["buy(uint256,bool,bool)"](0, true, true, {value: amtSpent, gasPrice: 0});
    // Max number of DUBLR tokens that could be bought == Math.trunc(300000 * 1e9 / 2500) == 120B
    // Max number in sell order == 20B (so the other 100B DUBLR are not bought from the sell order)
    // Amt spent on first 20B tokens = 2e10 * 2500 / 1e9 = 50000 ETH
    // Remaining ETH to spend on minting = 300000 - 50000 == 250000 ETH
    // Amount of tokens that can be minted at this price == 250000 * 1e9 / 5000 == 50B
    expect(await contract0.balanceOf(wallet[2].address, {gasPrice: 0})).to.equal(2e10 + 5e10);
    const ethBalance0_1 = await wallet[0].getBalance();
    const ethBalance1_1 = await wallet[1].getBalance();
    const ethBalance2_1 = await wallet[2].getBalance();
    expect(ethBalance2_1.sub(ethBalance2_0)).to.equal(-amtSpent);
    // Fee is 50000 * 0.0015 == 75
    // 50000 spent by buyer on first 20B tokens; 50000 - 75 = 49925 received by seller;
    expect(ethBalance1_1.sub(ethBalance1_0)).to.equal(49925);
    // Mint fees are all sent to owner, along with 75 for seller fees
    expect(ethBalance0_1.sub(ethBalance0_0)).to.equal(250000 + 75)
    expect(await contract0.orderBookSize()).to.equal(0);
  });

  it("Mint price over 1.0 ETH per DUBLR", async () => {
    await contract0._owner_setMinSellOrderValueETHWEI(0);
    const contract1 = await contract0.connect(wallet[1]);

    // Move forward 25 doubling periods (mint price will be close to 145 ETH per DUBLR)
    await ethers.provider.send("evm_increaseTime", [3600 * 24 * DOUBLING_PERIOD_DAYS * 25]);
    await ethers.provider.send("evm_mine");
    const mintPrice = await contract0.mintPrice();
    expect(mintPrice * 1e-9).to.be.closeTo(145, 0.25);

    // Try buying 3.5 DUBLR coins (the ETH equivalent of 0.5 DUBLR should be returned as change after minting)
    const ethBalance0_0 = await wallet[0].getBalance();
    const ethBalance1_0 = await wallet[1].getBalance();
    const amt0 = Math.ceil(mintPrice * 1e-9 * 3.5);
    const amt0Expected = Math.ceil(mintPrice * 1e-9 * 3);
    await contract1["buy(uint256,bool,bool)"](0, true, true, {value: amt0, gasPrice: 0});
    expect(await contract0.balanceOf(wallet[1].address, {gasPrice: 0})).to.equal(3);
    const ethBalance0_1 = await wallet[0].getBalance();
    const ethBalance1_1 = await wallet[1].getBalance();
    expect(ethBalance1_1.sub(ethBalance1_0)).to.equal(-amt0Expected);
    expect(ethBalance0_1.sub(ethBalance0_0)).to.equal(amt0Expected);

    // Try buying 7.9 DUBLR coins (the ETH equivalent of 0.9 DUBLR should be returned as change after minting)
    const amt1 = Math.ceil(mintPrice * 1e-9 * 7.9);
    const amt1Expected = Math.ceil(mintPrice * 1e-9 * 7);
    await contract1["buy(uint256,bool,bool)"](0, true, true, {value: amt1, gasPrice: 0});
    expect(await contract0.balanceOf(wallet[1].address, {gasPrice: 0})).to.equal(3 + 7);
    const ethBalance0_2 = await wallet[0].getBalance();
    const ethBalance1_2 = await wallet[1].getBalance();
    expect(ethBalance1_2.sub(ethBalance1_1)).to.equal(-amt1Expected);
    expect(ethBalance0_2.sub(ethBalance0_1)).to.equal(amt1Expected);

    // Try buying 8.0 DUBLR coins (need to round up since the price is about 145.2 ETH per DUBLR
    const amt2 = Math.ceil(mintPrice * 1e-9 * 8);
    await contract1["buy(uint256,bool,bool)"](0, true, true, {value: amt2, gasPrice: 0});
    expect(await contract0.balanceOf(wallet[1].address, {gasPrice: 0})).to.equal(3 + 7 + 8);
    const ethBalance0_3 = await wallet[0].getBalance();
    const ethBalance1_3 = await wallet[1].getBalance();
    expect(ethBalance1_3.sub(ethBalance1_2)).to.equal(-amt2);
    expect(ethBalance0_3.sub(ethBalance0_2)).to.equal(amt2);
  });

  it("Unpayable seller", async () => {
    await contract0._owner_setMinSellOrderValueETHWEI(0);
    const contract1 = await contract0.connect(wallet[1]);
    const unpayableSeller = await deployContract(wallet[2], UnpayableSeller, []);
    await contract0["buy(uint256,bool,bool)"](0, true, true, {value: 10});  // Mint 10 ETH worth => 2000000 DUBLR
    // Give the unpayable seller contract a balance
    await contract0._owner_enableTransferToContracts(true);
    await contract0["transfer(address,uint256)"](unpayableSeller.address, 2000000);
    const ethBalance0_0 = await wallet[0].getBalance();
    const ethBalance1_0 = await wallet[1].getBalance();
    await unpayableSeller.sell(contract0.address, initialMintPriceETHPerDUBLR_x1e9 - 1, 2000000, {gasPrice: 0});
    // Try buying the sell order (there is no market taker fee, because order is too small).
    // This should succeed, but the seller payment should be forfeited.
    await expect(contract1["buy(uint256,bool,bool)"](0, true, true, {value: 10, gasPrice: 0}))
            .to.emit(contract0, "Unpayable").withArgs(unpayableSeller.address, 10, "0x");
    const ethBalance0_1 = await wallet[0].getBalance();
    const ethBalance1_1 = await wallet[1].getBalance();
    expect(ethBalance1_1.sub(ethBalance1_0)).to.equal(-10); // Buyer spent 10 ETH wei
    expect(ethBalance0_1.sub(ethBalance0_0)).to.equal(10);  // Fees (1) and seller payment (9) go to owner, not seller
  });

  it("Unpayable buyer", async () => {
    dublr = await Dublr.deploy(10 * 1e9, 1);  // Re-deploy Dublr with 10 ETH == 1 DUBLR
    await dublr.deployed();
    await dublr._owner_setMinSellOrderValueETHWEI(0);
    const unpayableBuyer = await deployContract(wallet[1], UnpayableBuyer, []);
    // Give unpayableBuyer contract an ETH balance
    await wallet[0].sendTransaction({to: unpayableBuyer.address, value: 100, gasLimit: 3e7});
    // Then disable further ETH payments
    await unpayableBuyer.makePayable(false);
    // Can buy multiples of 10
    await unpayableBuyer.buy(dublr.address, {value: 20});
    // Can't buy if there is any change due
    await expect(unpayableBuyer.buy(dublr.address, {value: 25})).to.be.revertedWith("Can't refund change");
  });
  
  it("Heap stress test", async () => {
    // Create a new Dublr contract so we can fund with a higher amount than the other tests use
    const numWallets = 20;
    dublr = await Dublr.deploy(initialMintPriceETHPerDUBLR_x1e9, numWallets * 100);
    await dublr.deployed();
    await dublr._owner_setMinSellOrderValueETHWEI(0);
    const wallets = [];
    const contracts = [];
    const prices = [];
    for (var i = 0; i < numWallets; i++) {  // Create a heap containing `i` orders
        // Create wallets[i] and fund it with 100 DUBLR
        const wallet_i = await ethers.Wallet.createRandom().connect(ethers.provider);
        await network.provider.send("hardhat_setBalance", [wallet_i.address, "0x100000000000000"]);
        wallets.push(wallet_i);
        await dublr["transfer(address,uint256)"](wallet_i.address, 100);
        // Create a connection from wallets[i] to the new contract
        const contracti = await dublr.connect(wallet_i);
        contracts.push(contracti);
        // Create a sell order of random price
        const price = Math.floor(Math.random() * 100) + 1;
        prices.push(price);
        await contracti.sell(price, 100);
        expect(await contracti.orderBookSize()).to.equal(i + 1);
        // Mutate `i` random elements (selected with replacement) in the heap of size `i`, and test heap properties
        for (var j = 0; j <= i; j++) {
            // Check that the min-heap property holds for the whole heap
            const heapPrices = (await dublr.allSellOrders()).map(x => BigNumber.from(x[0]).toNumber());
            for (var k = 0; k < heapPrices.length; k++) {
                if (k * 2 + 1 < heapPrices.length) {
                    expect(heapPrices[k]).is.lessThanOrEqual(heapPrices[k * 2 + 1]);
                }
                if (k * 2 + 2 < heapPrices.length) {
                    expect(heapPrices[k]).is.lessThanOrEqual(heapPrices[k * 2 + 2]);
                }
            }
            // Check that the sorted prices for the sell order from each wallet equals the sorted prices in the heap
            const pricesSorted = [...prices].sort((a, b) => a - b);
            const heapPricesSorted = heapPrices.sort((a, b) => a - b);
            expect(pricesSorted).to.deep.equal(heapPricesSorted);
            // Randomly create a new order for a random wallet that already has an order in the heap.
            // This exercises the order cancelation code (which removes from the heap) and the order
            // creation code (which inserts into the heap).
            const idx = Math.floor(Math.random() * i);
            const newPrice = Math.floor(Math.random() * 100) + 1;
            prices[idx] = newPrice;
            await contracts[idx].sell(newPrice, 100);
        }
    }
  });
});
