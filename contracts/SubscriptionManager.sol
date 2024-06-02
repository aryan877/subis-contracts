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
        bool isActive;
    }

    uint256 public constant CHARGE_INTERVAL = 1 days;
    uint256 public nextChargeTimestamp;

    address public owner;
    string public name;
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
    event Subscribed(
        address indexed subscriber,
        uint256 indexed planId,
        uint256 timestamp
    );
    event Unsubscribed(
        address indexed subscriber,
        uint256 indexed planId,
        uint256 timestamp
    );
    event NextPaymentTimestampUpdated(
        address indexed subscriber,
        uint256 indexed planId,
        uint256 timestamp
    );
    event FundsWithdrawn(uint256 amount);
    event SubscriptionFeePaid(
        address indexed subscriber,
        uint256 indexed planId,
        uint256 amount,
        uint256 timestamp
    );
    event PaymentFailed(
        address indexed subscriber,
        uint256 indexed planId,
        uint256 subscriptionFeeWei,
        uint256 timestamp
    );
    event SubscriberRefunded(
        address indexed subscriber,
        uint256 indexed planId,
        uint256 amount,
        uint256 timestamp
    );

    constructor(
        address _owner,
        address _priceFeedAddress,
        string memory _name
    ) {
        owner = _owner;
        priceFeed = AggregatorV3Interface(_priceFeedAddress);
        name = _name;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    function updatePaymaster(address _newPaymaster) external onlyOwner {
        paymaster = _newPaymaster;
        emit PaymasterUpdated(_newPaymaster);
    }

    function chargeExpiredSubscriptions() external onlyOwner {
        require(
            block.timestamp >= nextChargeTimestamp,
            "Next charge timestamp not reached"
        );

        for (uint256 i = 0; i < planIds.length; i++) {
            uint256 planId = planIds[i];
            if (plans[planId].exists && plans[planId].isLive) {
                chargeExpiredSubscriptionsForPlan(planId);
            }
        }

        // Set the next charge timestamp to 12:00 UTC (midnight) of the following day
        uint256 currentTimestamp = block.timestamp;

        (
            uint256 currentYear,
            uint256 currentMonth,
            uint256 currentDay
        ) = DateTimeLibrary.timestampToDate(currentTimestamp);

        uint256 nextDay = currentDay + 1;
        uint256 nextMonth = currentMonth;
        uint256 nextYear = currentYear;

        // if next day is in the next month
        if (
            nextDay > DateTimeLibrary._getDaysInMonth(currentYear, currentMonth)
        ) {
            nextDay = 1;
            nextMonth += 1;

            // if next month is in the next year
            if (nextMonth > 12) {
                nextMonth = 1;
                nextYear += 1;
            }
        }

        nextChargeTimestamp = DateTimeLibrary.timestampFromDateTime(
            nextYear,
            nextMonth,
            nextDay,
            0,
            0,
            0
        );
    }

    function chargeExpiredSubscriptionsForPlan(uint256 planId) internal {
        for (uint256 i = 0; i < planSubscribers[planId].length; i++) {
            address subscriber = planSubscribers[planId][i];
            Subscription storage subscription = subscriptions[subscriber];

            if (
                subscription.isActive &&
                subscription.planId == planId &&
                block.timestamp >= subscription.nextPaymentTimestamp
            ) {
                uint256 subscriptionFeeWei = convertUSDtoETH(
                    plans[planId].feeUSD
                );

                chargeWallet(subscriber, subscriptionFeeWei);

                if (subscription.isActive) {
                    subscription.nextPaymentTimestamp = getNextMonthSameDay();
                    emit SubscriptionFeePaid(
                        subscriber,
                        planId,
                        subscriptionFeeWei,
                        block.timestamp
                    );
                    emit NextPaymentTimestampUpdated(
                        subscriber,
                        planId,
                        subscription.nextPaymentTimestamp
                    );
                } else {
                    emit PaymentFailed(
                        subscriber,
                        planId,
                        subscriptionFeeWei,
                        block.timestamp
                    );
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
        uint256 planId = ++planCount;
        plans[planId] = Plan(planId, name, feeUSD, true, false);
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
        for (uint256 i = 0; i < planCount; i++) {
            allPlans[i] = plans[planIds[i]];
        }
        return allPlans;
    }

    function getLivePlans() external view returns (Plan[] memory) {
        uint256 livePlanCount = 0;
        for (uint256 i = 0; i < planCount; i++) {
            if (plans[planIds[i]].isLive) {
                livePlanCount++;
            }
        }

        Plan[] memory livePlans = new Plan[](livePlanCount);
        uint256 counter = 0;
        for (uint256 i = 0; i < planCount; i++) {
            if (plans[planIds[i]].isLive) {
                livePlans[counter++] = plans[planIds[i]];
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
        return convertETHtoUSD(balance);
    }

    function getTotalSubscribers() external view returns (uint256) {
        uint256 totalSubscribers = 0;
        for (uint256 i = 0; i < planIds.length; i++) {
            uint256 planId = planIds[i];
            if (plans[planId].exists && plans[planId].isLive) {
                totalSubscribers += planSubscribers[planId].length;
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
            if (currentPlanId == planId) {
                if (subscription.isActive) {
                    revert AlreadySubscribed();
                } else {
                    if (block.timestamp > subscription.nextPaymentTimestamp) {
                        // Case 1: Buying the same plan after the plan expiration period
                        uint256 subscriptionFeeWei = convertUSDtoETH(
                            plans[planId].feeUSD
                        );
                        chargeWallet(msg.sender, subscriptionFeeWei);
                        emit SubscriptionFeePaid(
                            msg.sender,
                            planId,
                            subscriptionFeeWei,
                            block.timestamp
                        );
                        subscription
                            .nextPaymentTimestamp = getNextMonthSameDay();
                        emit NextPaymentTimestampUpdated(
                            msg.sender,
                            planId,
                            subscription.nextPaymentTimestamp
                        );
                    } else {
                        // Case 2: Resuming the same plan within the plan expiration time
                        subscription.isActive = true;
                        emit Subscribed(msg.sender, planId, block.timestamp);
                    }
                    planSubscribers[planId].push(msg.sender);
                    return;
                }
            } else {
                if (block.timestamp > subscription.nextPaymentTimestamp) {
                    // Case 3: Buying a different plan after plan expiration date
                    uint256 subscriptionFeeWei = convertUSDtoETH(
                        plans[planId].feeUSD
                    );
                    chargeWallet(msg.sender, subscriptionFeeWei);
                    emit SubscriptionFeePaid(
                        msg.sender,
                        planId,
                        subscriptionFeeWei,
                        block.timestamp
                    );
                    subscription.nextPaymentTimestamp = getNextMonthSameDay();
                    emit NextPaymentTimestampUpdated(
                        msg.sender,
                        planId,
                        subscription.nextPaymentTimestamp
                    );
                } else {
                    // Case 4: Buying a different plan within the plan expiration date
                    uint256 currentPlanFeeWei = convertUSDtoETH(
                        plans[currentPlanId].feeUSD
                    );
                    uint256 newPlanFeeWei = convertUSDtoETH(
                        plans[planId].feeUSD
                    );

                    uint256 remainingSeconds = subscription
                        .nextPaymentTimestamp - block.timestamp;
                    uint256 remainingDays = remainingSeconds / 86400; // as 86400 seconds in a day

                    // calculating refund or charge based on upgrade/downgrade for remaining days in the subscription period
                    uint256 currentPlanFeePerDay = currentPlanFeeWei /
                        DateTimeLibrary._getDaysInMonth(
                            DateTimeLibrary.getYear(
                                subscription.nextPaymentTimestamp
                            ),
                            DateTimeLibrary.getMonth(
                                subscription.nextPaymentTimestamp
                            )
                        );
                    uint256 newPlanFeePerDay = newPlanFeeWei /
                        DateTimeLibrary._getDaysInMonth(
                            DateTimeLibrary.getYear(
                                subscription.nextPaymentTimestamp
                            ),
                            DateTimeLibrary.getMonth(
                                subscription.nextPaymentTimestamp
                            )
                        );

                    uint256 currentPlanRemainingFee = currentPlanFeePerDay *
                        remainingDays;
                    uint256 newPlanRemainingFee = newPlanFeePerDay *
                        remainingDays;

                    if (newPlanRemainingFee > currentPlanRemainingFee) {
                        uint256 feeDifferenceWei = newPlanRemainingFee -
                            currentPlanRemainingFee;
                        chargeWallet(msg.sender, feeDifferenceWei);
                    } else if (currentPlanRemainingFee > newPlanRemainingFee) {
                        uint256 refundAmountWei = currentPlanRemainingFee -
                            newPlanRemainingFee;
                        _refundSubscriber(msg.sender, refundAmountWei);
                    }
                }

                emit Unsubscribed(msg.sender, currentPlanId, block.timestamp);
                removeSubscriber(currentPlanId, msg.sender);
            }
        } else {
            // Case 5: Buying a new subscription plan (new user)
            uint256 subscriptionFeeWei = convertUSDtoETH(plans[planId].feeUSD);
            chargeWallet(msg.sender, subscriptionFeeWei);
            emit SubscriptionFeePaid(
                msg.sender,
                planId,
                subscriptionFeeWei,
                block.timestamp
            );
            subscription.nextPaymentTimestamp = getNextMonthSameDay();
            emit NextPaymentTimestampUpdated(
                msg.sender,
                planId,
                subscription.nextPaymentTimestamp
            );
        }

        subscription.planId = planId;
        subscription.isActive = true;
        planSubscribers[planId].push(msg.sender);
        emit Subscribed(msg.sender, planId, block.timestamp);
    }

    function unsubscribe() public {
        Subscription storage subscription = subscriptions[msg.sender];
        uint256 currentPlanId = subscription.planId;

        if (!plans[currentPlanId].exists) revert InvalidPlan();

        subscription.isActive = false;
        emit Unsubscribed(msg.sender, currentPlanId, block.timestamp);
        removeSubscriber(currentPlanId, msg.sender);
    }

    function getNextMonthSameDay() internal view returns (uint256) {
        uint256 currentTimestamp = block.timestamp;
        (uint256 year, uint256 month, uint256 day) = DateTimeLibrary
            .timestampToDate(currentTimestamp);

        month += 1;
        if (month > 12) {
            year += 1;
            month = 1;
        }

        uint256 daysInNextMonth = DateTimeLibrary._getDaysInMonth(year, month);
        if (day > daysInNextMonth) {
            day = daysInNextMonth;
        }

        // Set the next charge timestamp to next month 12:00 UTC (midnight)
        return DateTimeLibrary.timestampFromDateTime(year, month, day, 0, 0, 0);
    }

    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance == 0) revert InsufficientBalance();

        (bool success, ) = owner.call{value: balance}("");
        require(success, "Withdrawal failed");

        emit FundsWithdrawn(balance);
    }

    function chargeWallet(address subscriber, uint256 amount) internal {
        ISubscriptionAccount subscriptionAccount = ISubscriptionAccount(
            subscriber
        );
        try subscriptionAccount.chargeWallet(amount) {} catch {
            subscriptions[subscriber].isActive = false;
            revert InsufficientBalance();
        }
    }

    function _refundSubscriber(address subscriber, uint256 amount) internal {
        if (address(this).balance < amount) {
            revert InsufficientBalance();
        }
        (bool success, ) = payable(subscriber).call{value: amount}("");
        require(success, "Refund failed");

        emit SubscriberRefunded(
            subscriber,
            subscriptions[subscriber].planId,
            amount,
            block.timestamp
        );
    }

    function refundSubscriber(
        address subscriber,
        uint256 refundAmount
    ) external onlyOwner {
        if (!plans[subscriptions[subscriber].planId].exists)
            revert InvalidPlan();

        _refundSubscriber(subscriber, refundAmount);
    }

    function removeSubscriber(uint256 planId, address subscriber) internal {
        address[] storage subscribers = planSubscribers[planId];
        for (uint256 i = 0; i < subscribers.length; i++) {
            if (subscribers[i] == subscriber) {
                subscribers[i] = subscribers[subscribers.length - 1];
                subscribers.pop();
                break;
            }
        }
    }

    receive() external payable {}
}
