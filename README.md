# DECENTRALIZED STABLE COIN (DSC)

## About

1. Create a basic account abstraction contract on Ethereum:
A EOA is the owner of the MinimalAccount Contract which implements account abstraction. This way MinimalAccount constitutes a smart contract wallet can execute transactions on behalf of the wallet owner. The interesting feature of this is that the wallet can be transferred to a different owner whithout revealing the private key. Another way to validate a transaction could be that the EOA needs to hold an specific NFT.
2. Create a basic account abstraction contract on ZkSync.
3. Deploy, and send a userOp / transaction through them (only ZkSync).

## Notes

Zksync uses multiple system contracts to handle operations such as deploying a contract. On Ethereum, contracts are deployed by sending a transaction without a receiver. That way the nodes know it's a deployment and not a regular transaction.

### ZkSync Transaction Type 113 (0x71)

Phase 1: Validation
1. The user sends the transaction to the ZkSync API client (like a "light node").
2. The ZkSync API client checks if the nonce is unique by querying the NonceHolder system contract: the NonceHolder contract stores the nonce for each account/contract.
3. The ZkSync API client calls validateTransaction, which MUST update the nonce in the NonceHolder contract. The msg.sender is always the bootloader system contract (like a super admin) for a 113 transaction (gets automatically rerouter to the bootloader contract).
4. The ZkSync API client checks if nonce is updated.
5. The ZkSync API client calls payForTransaction, or prepareForPaymaster & validateAndPayForPaymasterTransaction (checks if there are engouh funds to pay for the transaction).
6. The ZkSync API client verifies that the bootloader gets paid.

Phase 2: Execution
1. The ZkSync API client passes the validated transaction to the main node / sequencer (as of today, they are the same).
2. Main node will call the executeTransaction function.
3. If a paymaster is used, the postTransaction is called.

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

# accounts to deploy/interact with contracts
ACCOUNT_NAME="account name"
ACCOUNT_ADDRESS="account address"

```

Update chain ids in the HelperConfig.s.sol file for the chain you want to configure:

- Ethereum: 1 | Sepolia: 11155111
- Base: 8453 | Base sepolia: 84532
- Bsc: 56 | Bsc Testnet: 97

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

