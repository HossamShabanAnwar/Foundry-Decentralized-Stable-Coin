# EARN STABLE COIN

![Version](https://img.shields.io/badge/version-1.0.0-blue.svg?style=for-the-badge)
![Forge](https://img.shields.io/badge/forge-v0.2.0-blue.svg?style=for-the-badge)
![Solc](https://img.shields.io/badge/solc-v0.8.20-blue.svg?style=for-the-badge)

[![LinkedIn: hossamanany](https://img.shields.io/badge/LinkedIn-0a66c2?style=for-the-badge&logo=LinkedIn&logoColor=f5f5f5)](https://linkedin.com/in/hossamanany)
[![Twitter: hsmanany](https://img.shields.io/badge/@hsmanany?style=for-the-badge&logo=X)](https://twitter.com/hsmanany)


## About
This repo contains a collateralized stable coin implementation. The system is desinged to be as minimal as possible, and have the tokens maintain the USD price
This stablecoin has the properties:

1. Relative Stability: Anchored or Pegged - 1 USD
    1. Chainlink Price feed
    2. Set a function to exchange Collateral -> USD
2. Stability Mechanism (Minting): Algorithmic (Decentralized)
    1. People can only mint the stablecoin with enough collateral (coded)
3. Collateral: Exogenous/Endogenous (Crypto)
    1. wETH
    2. wBTC

The collaterall tokens used are wrapped BTC and wrapped ETH.

TODO:  
1. Fee and interest payment with EARN token.
2. Automatic liquidation on price drop

## Installation

### Install dependencies
```bash
$ make install
```

## Usage
Before running any commands, create a .env file and add the following environment variables:
```bash
# network configs
RPC_LOCALHOST="http://127.0.0.1:8545"

# ethereum nework
RPC_ETH_SEPOLIA=<rpc url>
RPC_ETH_MAIN=<rpc url>
ETHERSCAN_KEY=<api key>

```

### Run tests
```bash
$ forge test
```

### Deploy contract on testnet
```bash
$ make deploy-testnet
```

### Deploy contract on mainnet
```bash
$ make deploy-mainnet
```

## Deployments

### Testnet


## Author

👤 **Hossam Elanany**

* Twitter: [@hsmanany](https://twitter.com/hsmanany)
* Github: [@HossamElanany](https://github.com/hossamanany)
* LinkedIn: [@HossamElanany](https://linkedin.com/in/hossamanany)

Copyright © 2024 [Hossam Elanany](https://github.com/hossamanany).

This project is [MIT](https://github.com/hossamanany/Foundry-Decentralized-Stable-Coin/blob/master/LICENSE) licensed.


