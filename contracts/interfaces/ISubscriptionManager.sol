// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISubscriptionManager {
    function getSubscriptionFee(uint256 planId) external view returns (uint256);

    function convertUSDtoETH(uint256 amountUSD) external view returns (uint256);

    function isSubscriptionActive(
        address subscriber,
        uint256 planId
    ) external view returns (bool);

    function subscribe(address subscriber, uint256 planId) external;

    function unsubscribe(address subscriber, uint256 planId) external;

    function withdraw() external;
}
