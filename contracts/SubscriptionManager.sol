// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/ISubscriptionManager.sol";
import "./interfaces/ISubscriptionAccount.sol";
import "./libraries/DateTimeLibrary.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title SubscriptionManager
 * @dev This contract manages subscriptions for subscription accounts.
 */
contract SubscriptionManager is ISubscriptionManager {
    using DateTimeLibrary for uint256;

    struct Subscription {
        uint256 planId;
        uint256 nextPaymentTimestamp;
    }

    uint256 public lastChargeTimestamp;
    uint256 public constant CHARGE_INTERVAL = 1 days;

    address public owner;
    uint256 public planCount;
    address public paymaster;
    mapping(uint256 => Plan) public plans;
    mapping(address => Subscription) public subscriptions;
    mapping(uint256 => address[]) public planSubscribers;
    uint256[] public planIds;

    AggregatorV3Interface internal priceFeed;

    // Custom errors
    error AlreadySubscribed();
    error OnlyOwner();
    error InsufficientBalance();
    error InvalidPlan();
    error UnauthorizedAccount();
    error InsufficientPayment();
    error PlanNotLive();
    error PlanAlreadyLive();
    error SubscriptionNotActive();

    // Events
    event PaymasterUpdated(address indexed newPaymaster);
    event PlanCreated(uint256 indexed planId, string name, uint256 feeUSD);
    event PlanUpdated(uint256 indexed planId, string name, uint256 newFeeUSD);
    event PlanDeleted(uint256 indexed planId);
    event PlanLive(uint256 indexed planId);
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

    constructor(address _owner, address _priceFeedAddress) {
        owner = _owner;
        priceFeed = AggregatorV3Interface(_priceFeedAddress);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    function updatePaymaster(address _newPaymaster) external onlyOwner {
        paymaster = _newPaymaster;
        emit PaymasterUpdated(_newPaymaster);
    }

    function chargeExpiredSubscriptions() external {
        require(
            block.timestamp >= lastChargeTimestamp + CHARGE_INTERVAL,
            "Charge interval not reached"
        );

        for (uint256 i = 0; i < planIds.length; i++) {
            uint256 planId = planIds[i];
            if (plans[planId].exists && plans[planId].isLive) {
                chargeExpiredSubscriptionsForPlan(planId);
            }
        }

        lastChargeTimestamp = block.timestamp;
    }

    function chargeExpiredSubscriptionsForPlan(uint256 planId) internal {
        for (uint256 i = 0; i < planSubscribers[planId].length; i++) {
            address subscriber = planSubscribers[planId][i];
            Subscription storage subscription = subscriptions[subscriber];

            if (
                subscription.planId == planId &&
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
                    subscription.nextPaymentTimestamp = getNextMonthSameDay();
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
        uint256 planId = planCount + 1;
        plans[planId] = Plan(name, feeUSD, true, false);
        planCount++;
        planIds.push(planId);
        emit PlanCreated(planId, name, feeUSD);
    }

    function updatePlan(
        uint256 planId,
        string calldata newName,
        uint256 newFeeUSD
    ) external onlyOwner {
        if (!plans[planId].exists) revert InvalidPlan();
        if (plans[planId].isLive) revert PlanAlreadyLive();

        plans[planId].name = newName;
        plans[planId].feeUSD = newFeeUSD;
        emit PlanUpdated(planId, newName, newFeeUSD);
    }

    function deletePlan(uint256 planId) external onlyOwner {
        if (!plans[planId].exists) revert InvalidPlan();
        if (plans[planId].isLive) revert PlanAlreadyLive();

        delete plans[planId];
        removePlanId(planId);
        planCount--;
        emit PlanDeleted(planId);
    }

    function removePlanId(uint256 planId) internal {
        for (uint256 i = 0; i < planIds.length; i++) {
            if (planIds[i] == planId) {
                planIds[i] = planIds[planIds.length - 1];
                planIds.pop();
                break;
            }
        }
    }

    function makePlanLive(uint256 planId) external onlyOwner {
        if (!plans[planId].exists) revert InvalidPlan();
        if (plans[planId].isLive) revert PlanAlreadyLive();

        plans[planId].isLive = true;
        emit PlanLive(planId);
    }

    function getSubscriptionFee(
        uint256 planId
    ) external view returns (uint256) {
        if (!plans[planId].exists) revert InvalidPlan();
        return plans[planId].feeUSD;
    }

    function getAllPlans() external view returns (Plan[] memory) {
        Plan[] memory allPlans = new Plan[](planCount);
        for (uint256 i = 1; i <= planCount; i++) {
            allPlans[i - 1] = plans[planIds[i - 1]];
        }
        return allPlans;
    }

    function getLivePlans() external view returns (Plan[] memory) {
        uint256 livePlanCount = 0;
        for (uint256 i = 1; i <= planCount; i++) {
            if (plans[planIds[i - 1]].isLive) {
                livePlanCount++;
            }
        }

        Plan[] memory livePlans = new Plan[](livePlanCount);
        uint256 counter = 0;
        for (uint256 i = 1; i <= planCount; i++) {
            if (plans[planIds[i - 1]].isLive) {
                livePlans[counter] = plans[planIds[i - 1]];
                counter++;
            }
        }
        return livePlans;
    }

    function isSubscriptionActive(
        address subscriber
    ) external view returns (bool) {
        Subscription storage subscription = subscriptions[subscriber];
        uint256 planId = subscription.planId;

        if (!plans[planId].exists) revert InvalidPlan();

        return block.timestamp < subscription.nextPaymentTimestamp;
    }

    function getSubscriberCount(
        uint256 planId
    ) external view returns (uint256) {
        return planSubscribers[planId].length;
    }

    function convertETHtoUSD(uint256 amountWei) public view returns (uint256) {
        uint256 ethPrice = getLatestPrice();
        uint256 amountUSD = (amountWei * ethPrice) / 1e18;
        return amountUSD;
    }

    function getTotalRevenue() external view returns (uint256) {
        uint256 balance = address(this).balance;
        uint256 totalRevenueUSD = convertETHtoUSD(balance);
        return totalRevenueUSD;
    }

    function getTotalSubscribers() external view returns (uint256) {
        uint256 totalSubscribers = 0;
        for (uint256 i = 1; i <= planIds.length; i++) {
            uint256 planId = planIds[i - 1];
            if (plans[planId].exists && plans[planId].isLive) {
                for (uint256 j = 0; j < planSubscribers[planId].length; j++) {
                    address subscriber = planSubscribers[planId][j];
                    if (
                        subscriptions[subscriber].planId == planId &&
                        block.timestamp <
                        subscriptions[subscriber].nextPaymentTimestamp
                    ) {
                        totalSubscribers++;
                    }
                }
            }
        }
        return totalSubscribers;
    }

    function subscribe(uint256 planId) external {
        if (!plans[planId].exists) revert InvalidPlan();
        if (!plans[planId].isLive) revert PlanNotLive();

        Subscription storage subscription = subscriptions[msg.sender];
        uint256 currentPlanId = subscription.planId;

        if (currentPlanId != 0) {
            if (currentPlanId == planId) revert AlreadySubscribed();

            uint256 currentPlanFeeUSD = plans[currentPlanId].feeUSD;
            uint256 newPlanFeeUSD = plans[planId].feeUSD;

            if (newPlanFeeUSD > currentPlanFeeUSD) {
                uint256 feeDifferenceUSD = newPlanFeeUSD - currentPlanFeeUSD;
                uint256 feeDifferenceWei = convertUSDtoETH(feeDifferenceUSD);

                ISubscriptionAccount subscriptionAccount = ISubscriptionAccount(
                    msg.sender
                );

                try
                    subscriptionAccount.chargeWallet(feeDifferenceWei)
                {} catch {
                    revert InsufficientBalance();
                }
            } else if (newPlanFeeUSD < currentPlanFeeUSD) {
                uint256 feeDifferenceUSD = currentPlanFeeUSD - newPlanFeeUSD;
                uint256 feeDifferenceWei = convertUSDtoETH(feeDifferenceUSD);

                if (address(this).balance < feeDifferenceWei) {
                    revert InsufficientBalance();
                }

                (bool success, ) = payable(msg.sender).call{
                    value: feeDifferenceWei
                }("");
                require(success, "Refund failed");
            }

            // Remove the subscriber from the current plan's subscribers list
            address[] storage currentPlanSubscribers = planSubscribers[
                currentPlanId
            ];
            for (uint256 i = 0; i < currentPlanSubscribers.length; i++) {
                if (currentPlanSubscribers[i] == msg.sender) {
                    currentPlanSubscribers[i] = currentPlanSubscribers[
                        currentPlanSubscribers.length - 1
                    ];
                    currentPlanSubscribers.pop();
                    break;
                }
            }

            emit Unsubscribed(msg.sender, currentPlanId);
        } else {
            uint256 subscriptionFeeUSD = plans[planId].feeUSD;
            uint256 subscriptionFeeWei = convertUSDtoETH(subscriptionFeeUSD);

            ISubscriptionAccount subscriptionAccount = ISubscriptionAccount(
                msg.sender
            );

            try subscriptionAccount.chargeWallet(subscriptionFeeWei) {} catch {
                revert InsufficientBalance();
            }

            emit SubscriptionFeePaid(msg.sender, planId, subscriptionFeeWei);
        }

        // Update the subscription details (for both new and existing subscriptions)
        subscription.planId = planId;
        subscription.nextPaymentTimestamp = getNextMonthSameDay();
        planSubscribers[planId].push(msg.sender);
        emit Subscribed(msg.sender, planId);
        emit NextPaymentTimestampUpdated(
            msg.sender,
            planId,
            subscription.nextPaymentTimestamp
        );
    }

    function unsubscribe() public {
        Subscription storage subscription = subscriptions[msg.sender];
        uint256 currentPlanId = subscription.planId;

        if (!plans[currentPlanId].exists) revert InvalidPlan();

        delete subscription.planId;
        delete subscription.nextPaymentTimestamp;

        // Remove the subscriber from the planSubscribers array
        address[] storage subscribers = planSubscribers[currentPlanId];
        for (uint256 i = 0; i < subscribers.length; i++) {
            if (subscribers[i] == msg.sender) {
                subscribers[i] = subscribers[subscribers.length - 1];
                subscribers.pop();
                break;
            }
        }

        emit Unsubscribed(msg.sender, currentPlanId);
    }

    function getNextMonthSameDay() internal view returns (uint256) {
        uint256 currentTimestamp = block.timestamp;
        (
            uint256 currentYear,
            uint256 currentMonth,
            uint256 currentDay
        ) = DateTimeLibrary.timestampToDate(currentTimestamp);

        uint256 nextMonth = currentMonth + 1;
        uint256 nextYear = currentYear;
        if (nextMonth > 12) {
            nextYear += 1;
            nextMonth = 1;
        }

        uint256 daysInNextMonth = DateTimeLibrary._getDaysInMonth(
            nextYear,
            nextMonth
        );
        uint256 nextDay = currentDay > daysInNextMonth
            ? daysInNextMonth
            : currentDay;

        return DateTimeLibrary.timestampFromDate(nextYear, nextMonth, nextDay);
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
