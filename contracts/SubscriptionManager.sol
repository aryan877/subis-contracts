// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "./interfaces/ISubscriptionManager.sol";

/**
 * @title SubscriptionManager
 * @dev This contract manages subscriptions for subscription accounts.
 * It allows creating subscription plans, subscribing, unsubscribing, and updating the next payment timestamp.
 * The business owner can withdraw the collected subscription fees.
 */
contract SubscriptionManager is ISubscriptionManager {
    struct Plan {
        uint256 feeUSD; // Subscription fee in USD (8 decimal places)
        bool exists;
    }

    address public owner; // The owner of the subscription manager
    uint256 public planCount; // The total number of subscription plans
    mapping(uint256 => Plan) public plans; // Mapping to store subscription plans
    mapping(address => mapping(uint256 => uint256)) public subscriptions; // Mapping to store subscription details for each subscriber and plan

    uint256 constant PAYMENT_RENEWAL_PERIOD = 30 days; // The period after which the subscription payment needs to be renewed
    AggregatorV3Interface internal priceFeed; // The Chainlink price feed for ETH/USD

    // Custom errors
    error AlreadySubscribed();
    error OnlyOwner();
    error InsufficientBalance();
    error InvalidPlan();
    error UnauthorizedAccount();
    error InsufficientPayment();

    // Events
    event PlanCreated(uint256 indexed planId, uint256 feeUSD);
    event PlanUpdated(uint256 indexed planId, uint256 newFeeUSD);
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

    /**
     * @dev Constructor function to initialize the subscription manager.
     * @param _priceFeedAddress The address of the Chainlink price feed contract.
     */
    constructor(address _priceFeedAddress) {
        owner = msg.sender;
        priceFeed = AggregatorV3Interface(_priceFeedAddress);
    }

    /**
     * @dev Modifier to restrict access to only the owner.
     */
    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    /**
     * @dev Process the subscription payment for a subscriber and plan.
     * @param subscriber The address of the subscriber.
     * @param planId The ID of the subscription plan.
     */
    function processSubscriptionPayment(
        address subscriber,
        uint256 planId
    ) external payable {
        if (!plans[planId].exists) revert InvalidPlan();

        uint256 subscriptionFeeUSD = plans[planId].feeUSD;
        uint256 subscriptionFeeWei = convertUSDtoETH(subscriptionFeeUSD);

        if (msg.value < subscriptionFeeWei) revert InsufficientPayment();

        // Update the next payment timestamp
        subscriptions[subscriber][planId] =
            block.timestamp +
            PAYMENT_RENEWAL_PERIOD;

        emit SubscriptionFeePaid(subscriber, planId, msg.value);
        emit NextPaymentTimestampUpdated(
            subscriber,
            planId,
            subscriptions[subscriber][planId]
        );
    }

    /**
     * @dev Convert an amount from USD to ETH using the Chainlink price feed.
     * @param amountUSD The amount in USD (with 8 decimal places).
     * @return The equivalent amount in ETH (in wei).
     */
    function convertUSDtoETH(uint256 amountUSD) public view returns (uint256) {
        uint256 ethPrice = getLatestPrice();

        // Convert the ETH amount to wei using decimal calculations
        uint256 amountWei = (amountUSD * 1e18) / ethPrice;

        return amountWei;
    }

    /**
     * @dev Get the latest ETH/USD price from the Chainlink price feed.
     * @return The latest price.
     */
    function getLatestPrice() public view returns (uint256) {
        (, int price, , , ) = priceFeed.latestRoundData();

        // This value is already in the correct format (USD with 8 decimals).
        return uint256(price);
    }

    /**
     * @dev Create a new subscription plan.
     * @param feeUSD The subscription fee in USD for the plan.
     */
    function createPlan(uint256 feeUSD) external onlyOwner {
        uint256 planId = planCount;
        plans[planId] = Plan(feeUSD, true);
        planCount++;
        emit PlanCreated(planId, feeUSD);
    }

    /**
     * @dev Update an existing subscription plan.
     * @param planId The ID of the subscription plan.
     * @param newFeeUSD The new subscription fee in USD for the plan.
     */
    function updatePlan(uint256 planId, uint256 newFeeUSD) external onlyOwner {
        if (!plans[planId].exists) revert InvalidPlan();

        plans[planId].feeUSD = newFeeUSD;
        emit PlanUpdated(planId, newFeeUSD);
    }

    /**
     * @dev Get the subscription fee for a specific plan.
     * @param planId The ID of the subscription plan.
     * @return The subscription fee in USD for the plan.
     */
    function getSubscriptionFee(
        uint256 planId
    ) external view override returns (uint256) {
        if (!plans[planId].exists) revert InvalidPlan();

        return plans[planId].feeUSD;
    }

    /**
     * @dev Get all available subscription plans.
     * @return An array of subscription plan IDs.
     */
    function getAvailablePlans() external view returns (uint256[] memory) {
        uint256[] memory availablePlans = new uint256[](planCount);
        for (uint256 i = 0; i < planCount; i++) {
            availablePlans[i] = i;
        }
        return availablePlans;
    }

    /**
     * @dev Check if a subscription is active for a subscriber and plan.
     * @param subscriber The address of the subscriber.
     * @param planId The ID of the subscription plan.
     * @return A boolean indicating if the subscription is active.
     */
    function isSubscriptionActive(
        address subscriber,
        uint256 planId
    ) external view override returns (bool) {
        if (!plans[planId].exists) revert InvalidPlan();

        return subscriptions[subscriber][planId] > block.timestamp;
    }

    /**
     * @dev Subscribe a subscriber to a specific plan.
     * @param subscriber The address of the subscriber.
     * @param planId The ID of the subscription plan.
     */
    function subscribe(address subscriber, uint256 planId) external override {
        if (!plans[planId].exists) revert InvalidPlan();
        if (subscriptions[subscriber][planId] != 0) revert AlreadySubscribed();

        subscriptions[subscriber][planId] = block.timestamp;
        emit Subscribed(subscriber, planId);
    }

    /**
     * @dev Unsubscribe a subscriber from a specific plan.
     * @param subscriber The address of the subscriber.
     * @param planId The ID of the subscription plan.
     */
    function unsubscribe(address subscriber, uint256 planId) external override {
        if (!plans[planId].exists) revert InvalidPlan();

        delete subscriptions[subscriber][planId];
        emit Unsubscribed(subscriber, planId);
    }

    /**
     * @dev Withdraw the collected subscription fees.
     */
    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance == 0) revert InsufficientBalance();

        (bool success, ) = owner.call{value: balance}("");
        require(success, "Withdrawal failed");

        emit FundsWithdrawn(balance);
    }

    /**
     * @dev Receive function to accept ETH payments.
     */
    receive() external payable {}
}
