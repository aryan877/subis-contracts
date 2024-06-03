## Contracts README

The Subis contracts repository contains the smart contracts for the decentralized subscription management system. The main contracts are:

- `AAFactory.sol`: Factory contract for deploying Subscription Account contracts.
- `ManagerFactory.sol`: Factory contract for deploying Subscription Manager contracts.
- `SubscriptionAccount.sol`: Smart contract wallet for subscribers, enabling gasless transactions and daily spending limits.
- `SubscriptionManager.sol`: Contract for managing subscription plans, subscriptions, and charging subscribers.
- `SubscriptionPaymaster.sol`: Paymaster contract for handling gasless transactions, funded by the subscription provider.

The contracts utilize Chainlink Price Feeds to convert prices between USD and ETH. The repository also includes interfaces and libraries.
