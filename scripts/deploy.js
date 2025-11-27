const { ethers } = require("hardhat");

async function main() {
  const LoanStreamChain = await ethers.getContractFactory("LoanStreamChain");
  const loanStreamChain = await LoanStreamChain.deploy();

  await loanStreamChain.deployed();

  console.log("LoanStreamChain contract deployed to:", loanStreamChain.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
