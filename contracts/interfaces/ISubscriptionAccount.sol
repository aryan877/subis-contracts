// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISubscriptionAccount {
    function owner() external view returns (address);

    function convertUSDtoETH(uint256 amountUSD) external view returns (uint256);

    function chargeWallet(uint256 amount) external;
}
