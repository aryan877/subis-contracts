// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "./interfaces/ISubscriptionManager.sol";
import "./interfaces/ISubscriptionAccount.sol";

/**
 * @title SubscriptionManager
 * @dev This contract manages subscriptions for subscription accounts.
 */
contract SubscriptionManager is ISubscriptionManager {
    struct Plan {
        string name;
        uint256 feeUSD; // Subscription fee in USD (8 decimal places)
        bool exists;
    }

    struct Subscription {
        bool isSubscribed;
        bool isActive;
        uint256 nextPaymentTimestamp;
    }

    uint256 public lastChargeTimestamp;
    uint256 public constant CHARGE_INTERVAL = 1 days;

    address public owner;
    uint256 public planCount;
    mapping(uint256 => Plan) public plans;
    mapping(address => mapping(uint256 => Subscription)) public subscriptions;
    mapping(uint256 => address[]) public planSubscribers;

    uint256 constant PAYMENT_RENEWAL_PERIOD = 30 days;
    AggregatorV3Interface internal priceFeed;

    // Custom errors
    error AlreadySubscribed();
    error OnlyOwner();
    error InsufficientBalance();
    error InvalidPlan();
    error UnauthorizedAccount();
    error InsufficientPayment();

    // Events
    event PlanCreated(uint256 indexed planId, string name, uint256 feeUSD);
    event PlanUpdated(uint256 indexed planId, string name, uint256 newFeeUSD);
    event Subscribed(address indexed subscriber, uint256 indexed planId);
    event Unsubscribed(address indexed subscriber, uint256 indexed planId);
    event NextPaymentTimestampUpdated(
        address indexed subscriber,
        uint256 indexed planId,
        uint256 timestamp
    );
    event FundsWithdrawn(uint256 amount);
    event SubscriptionFeePaid(
        address indexed subscriber,
        uint256 indexed planId,
        uint256 amount
    );
    event PaymentFailed(
        address indexed subscriber,
        uint256 indexed planId,
        uint256 subscriptionFeeWei
    );

    constructor(address _priceFeedAddress) {
        owner = msg.sender;
        priceFeed = AggregatorV3Interface(_priceFeedAddress);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    function chargeExpiredSubscriptions() external {
        require(
            block.timestamp >= lastChargeTimestamp + CHARGE_INTERVAL,
            "Charge interval not reached"
        );

        for (uint256 planId = 0; planId < planCount; planId++) {
            if (plans[planId].exists) {
                chargeExpiredSubscriptionsForPlan(planId);
            }
        }

        lastChargeTimestamp = block.timestamp;
    }

    function chargeExpiredSubscriptionsForPlan(uint256 planId) internal {
        for (uint256 i = 0; i < planSubscribers[planId].length; i++) {
            address subscriber = planSubscribers[planId][i];
            Subscription storage subscription = subscriptions[subscriber][
                planId
            ];

            if (
                subscription.isSubscribed &&
                block.timestamp >= subscription.nextPaymentTimestamp
            ) {
                uint256 subscriptionFeeUSD = plans[planId].feeUSD;
                uint256 subscriptionFeeWei = convertUSDtoETH(
                    subscriptionFeeUSD
                );

                ISubscriptionAccount subscriptionAccount = ISubscriptionAccount(
                    subscriber
                );

                try subscriptionAccount.chargeWallet(subscriptionFeeWei) {
                    subscription.nextPaymentTimestamp =
                        block.timestamp +
                        PAYMENT_RENEWAL_PERIOD;
                    subscription.isActive = true;
                    emit SubscriptionFeePaid(
                        subscriber,
                        planId,
                        subscriptionFeeWei
                    );
                    emit NextPaymentTimestampUpdated(
                        subscriber,
                        planId,
                        subscription.nextPaymentTimestamp
                    );
                } catch {
                    subscription.isActive = false;
                    emit PaymentFailed(subscriber, planId, subscriptionFeeWei);
                }
            }
        }
    }

    function convertUSDtoETH(uint256 amountUSD) public view returns (uint256) {
        uint256 ethPrice = getLatestPrice();
        uint256 amountWei = (amountUSD * 1e18) / ethPrice;
        return amountWei;
    }

    function getLatestPrice() public view returns (uint256) {
        (, int price, , , ) = priceFeed.latestRoundData();
        return uint256(price);
    }

    function createPlan(
        string calldata name,
        uint256 feeUSD
    ) external onlyOwner {
        uint256 planId = planCount;
        plans[planId] = Plan(name, feeUSD, true);
        planCount++;
        emit PlanCreated(planId, name, feeUSD);
    }

    function updatePlan(
        uint256 planId,
        string calldata newName,
        uint256 newFeeUSD
    ) external onlyOwner {
        if (!plans[planId].exists) revert InvalidPlan();

        plans[planId].name = newName;
        plans[planId].feeUSD = newFeeUSD;
        emit PlanUpdated(planId, newName, newFeeUSD);
    }

    function getSubscriptionFee(
        uint256 planId
    ) external view returns (uint256) {
        if (!plans[planId].exists) revert InvalidPlan();
        return plans[planId].feeUSD;
    }

    function getAvailablePlans() external view returns (uint256[] memory) {
        uint256[] memory availablePlans = new uint256[](planCount);
        for (uint256 i = 0; i < planCount; i++) {
            availablePlans[i] = i;
        }
        return availablePlans;
    }

    function isSubscriptionActive(
        address subscriber,
        uint256 planId
    ) external view returns (bool) {
        if (!plans[planId].exists) revert InvalidPlan();
        return subscriptions[subscriber][planId].isActive;
    }

    function subscribe(uint256 planId) external {
        if (!plans[planId].exists) revert InvalidPlan();
        if (subscriptions[msg.sender][planId].isSubscribed)
            revert AlreadySubscribed();

        subscriptions[msg.sender][planId] = Subscription({
            isSubscribed: true,
            isActive: false,
            nextPaymentTimestamp: 0
        });
        planSubscribers[planId].push(msg.sender);
        emit Subscribed(msg.sender, planId);
    }

    function unsubscribe(uint256 planId) external {
        if (!plans[planId].exists) revert InvalidPlan();
        if (!subscriptions[msg.sender][planId].isSubscribed)
            revert UnauthorizedAccount();

        delete subscriptions[msg.sender][planId];

        // Remove the subscriber from the planSubscribers array
        for (uint256 i = 0; i < planSubscribers[planId].length; i++) {
            if (planSubscribers[planId][i] == msg.sender) {
                planSubscribers[planId][i] = planSubscribers[planId][
                    planSubscribers[planId].length - 1
                ];
                planSubscribers[planId].pop();
                break;
            }
        }

        emit Unsubscribed(msg.sender, planId);
    }

    function startSubscription(uint256 planId) external {
        if (!plans[planId].exists) revert InvalidPlan();
        Subscription storage subscription = subscriptions[msg.sender][planId];
        if (!subscription.isSubscribed) revert UnauthorizedAccount();

        uint256 subscriptionFeeUSD = plans[planId].feeUSD;
        uint256 subscriptionFeeWei = convertUSDtoETH(subscriptionFeeUSD);

        ISubscriptionAccount subscriptionAccount = ISubscriptionAccount(
            msg.sender
        );
        subscriptionAccount.chargeWallet(subscriptionFeeWei);

        subscription.nextPaymentTimestamp =
            block.timestamp +
            PAYMENT_RENEWAL_PERIOD;
        subscription.isActive = true;

        emit SubscriptionFeePaid(msg.sender, planId, subscriptionFeeWei);
        emit NextPaymentTimestampUpdated(
            msg.sender,
            planId,
            subscription.nextPaymentTimestamp
        );
    }

    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance == 0) revert InsufficientBalance();

        (bool success, ) = owner.call{value: balance}("");
        require(success, "Withdrawal failed");

        emit FundsWithdrawn(balance);
    }

    receive() external payable {}
}
