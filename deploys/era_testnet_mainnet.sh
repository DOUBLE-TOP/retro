#!/bin/bash

read -p "Select chain: 1) Mainnet 2) Testnet " chain
while [[ "$chain" != "1" && "$chain" != "2" ]]; do
    read -p "Please enter a valid option (1 or 2): " chain
done

if [[ "$chain" == "1" ]]; then
    echo "You selected Mainnet"
    chain="Mainnet"
elif [[ "$chain" == "2" ]]; then
    echo "You selected Testnet"
    chain="Testnet"
fi

read -p "Enter your private key:" WALLET_PRIVATE_KEY

. <(wget -qO- sh.doubletop.io) tools nodejs --force

npm init -y
npm install --save-dev hardhat
npm install -g npm@9.6.2

mkdir -p $HOME/greeter
cat <<EOF > $HOME/greeter/package.json
{
  "name": "greeter",
  "version": "1.0.0",
  "description": "",
  "main": "index.js",
  "scripts": {
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "keywords": [],
  "author": "",
  "license": "ISC",
  "devDependencies": {
    "@ethersproject/hash": "^5.7.0",
    "@ethersproject/web": "^5.7.1",
    "@matterlabs/hardhat-zksync-deploy": "^0.6.3",
    "@matterlabs/hardhat-zksync-solc": "^0.3.16",
    "@nomicfoundation/hardhat-toolbox": "^2.0.2",
    "@types/node": "^18.15.11",
    "ethers": "^5.7.2",
    "hardhat": "^2.13.0",
    "ts-node": "^10.9.1",
    "typescript": "^5.0.3",
    "zksync-web3": "^0.14.3"
  }
}
EOF

cd $HOME/greeter
npm install

if [ "$chain" == "Mainnet" ]; then
    cat <<EOF > $HOME/greeter/hardhat.config.ts
    import "@matterlabs/hardhat-zksync-deploy";
    import "@matterlabs/hardhat-zksync-solc";

    module.exports = {
    zksolc: {
        version: "1.3.6",
        compilerSource: "binary",
        settings: {},
    },
    defaultNetwork: "zkSyncMainnet",
    networks: {
        zkSyncMainnet: {
        url: "https://zksync2-mainnet.zksync.io",
        ethNetwork: "mainnet", 
        zksync: true,
        },
    },
    solidity: {
        version: "0.8.17",
    },
    };
EOF
fi

if [ "$chain" == "Testnet" ]; then
    cat <<EOF > $HOME/greeter/hardhat.config.ts
    import "@matterlabs/hardhat-zksync-deploy";
    import "@matterlabs/hardhat-zksync-solc";

    module.exports = {
    zksolc: {
        version: "1.3.6",
        compilerSource: "binary",
        settings: {},
    },
    defaultNetwork: "zkTestnet",
    networks: {
        zkTestnet: {
        url: "https://zksync2-testnet.zksync.dev", 
        ethNetwork: "https://eth-goerli.g.alchemy.com/v2/yJMD5nyv6ikOG7BEhD5tPpaTZcRdErQU",
        zksync: true,
        },
    },
    solidity: {
        version: "0.8.17",
    },
    };
EOF
fi

mkdir -p $HOME/greeter/contracts $HOME/greeter/deploy

cat <<EOF > $HOME/greeter/contracts/Greeter.sol
//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

contract Greeter {
    string private greeting;

    constructor(string memory _greeting) {
        greeting = _greeting;
    }

    function greet() public view returns (string memory) {
        return greeting;
    }

    function setGreeting(string memory _greeting) public {
        greeting = _greeting;
    }
}
EOF

npx hardhat compile

cat <<EOF > $HOME/greeter/deploy/deploy.ts
import { utils, Wallet } from "zksync-web3";
import * as ethers from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";

// An example of a deploy script that will deploy and call a simple contract.
export default async function (hre: HardhatRuntimeEnvironment) {
  console.log(`Running deploy script for the Greeter contract`);

  // Initialize the wallet.
  const wallet = new Wallet("$WALLET_PRIVATE_KEY");

  // Create deployer object and load the artifact of the contract we want to deploy.
  const deployer = new Deployer(hre, wallet);
  const artifact = await deployer.loadArtifact("Greeter");

  // Deposit some funds to L2 in order to be able to perform L2 transactions.
  const depositAmount = ethers.utils.parseEther("0.001");
  const depositHandle = await deployer.zkWallet.deposit({
    to: deployer.zkWallet.address,
    token: utils.ETH_ADDRESS,
    amount: depositAmount,
  });
  // Wait until the deposit is processed on zkSync
  await depositHandle.wait();

  // Deploy this contract. The returned object will be of a `Contract` type, similarly to ones in `ethers`.
  // `greeting` is an argument for contract constructor.
  const greeting = "Hi there!";
  const greeterContract = await deployer.deploy(artifact, [greeting]);

  // Show the contract info.
  const contractAddress = greeterContract.address;
  console.log(`${artifact.contractName} was deployed to ${contractAddress}`);

  // Call the deployed contract.
  const greetingFromContract = await greeterContract.greet();
  if (greetingFromContract == greeting) {
    console.log(`Contract greets us with ${greeting}!`);
  } else {
    console.error(`Contract said something unexpected: ${greetingFromContract}`);
  }

  // Edit the greeting of the contract
  const newGreeting = "Hey guys";
  const setNewGreetingHandle = await greeterContract.setGreeting(newGreeting);
  await setNewGreetingHandle.wait();

  const newGreetingFromContract = await greeterContract.greet();
  if (newGreetingFromContract == newGreeting) {
    console.log(`Contract greets us with ${newGreeting}!`);
  } else {
    console.error(`Contract said something unexpected: ${newGreetingFromContract}`);
  }
}
EOF

npx hardhat deploy-zksync

rm -rf $HOME/greeter/
