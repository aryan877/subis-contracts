// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISubscriptionManager {
    struct Plan {
        uint256 planId;
        string name;
        uint256 feeUSD;
        bool exists;
        bool isLive;
    }

    function getSubscriptionFee(uint256 planId) external view returns (uint256);

    function convertUSDtoETH(uint256 amountUSD) external view returns (uint256);

    function convertETHtoUSD(uint256 amountWei) external view returns (uint256);

    function isSubscriptionActive(
        address subscriber
    ) external view returns (bool);

    function subscribe(uint256 planId) external;

    function unsubscribe() external;

    function withdraw() external;

    function chargeExpiredSubscriptions() external;

    function updatePaymaster(address _newPaymaster) external;

    function createPlan(string calldata name, uint256 feeUSD) external;

    function updatePlan(
        uint256 planId,
        string calldata newName,
        uint256 newFeeUSD
    ) external;

    function deletePlan(uint256 planId) external;

    function makePlanLive(uint256 planId) external;

    function getAllPlans() external view returns (Plan[] memory);

    function getLivePlans() external view returns (Plan[] memory);

    function getTotalRevenue() external view returns (uint256);

    function getTotalSubscribers() external view returns (uint256);

    function getSubscriberCount(uint256 planId) external view returns (uint256);

    function refundSubscriber(
        address subscriber,
        uint256 refundAmount
    ) external;
}
