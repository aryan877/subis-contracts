## Cron README

The Subis cron repository contains a script that runs as a cron job to automatically charge subscribers whose subscription period has ended but the subscription is still active. The script:

- Runs daily at midnight (12:00 AM UTC)
- Interacts with the deployed Subscription Manager contract
- Charges the subscribers using the `chargeExpiredSubscriptions` function
- Logs the results of each run

The cron job ensures that subscribers are charged accurately based on their subscription terms.

Once the Subscription Manager is deployed through the frontend app, subscription owners can set up this cron job by providing the private key of the wallet that deployed the Subscription Manager and the address of the deployed Subscription Manager contract. This allows the cron job to interact with the specific Subscription Manager instance and charge users who have active subscriptions that have reached the end of their monthly period.

It's important to note that this cron job setup is a temporary fallback solution. In the future, when zkSync supports Chainlink Automation, it will provide a more decentralized and reliable approach for automating the charging process. Chainlink Automation enables the execution of smart contract functions based on predefined conditions or schedules, eliminating the need for centralized cron jobs.

Once Chainlink Automation is available on zkSync, the Subis platform will integrate it to automatically trigger the `chargeExpiredSubscriptions` function on the Subscription Manager contract at the specified intervals. This will ensure a fully decentralized and trustless mechanism for charging subscribers, enhancing the security and reliability of the subscription management process
