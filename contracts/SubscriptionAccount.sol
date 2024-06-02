// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IAccount.sol";
import "@matterlabs/zksync-contracts/l2/system-contracts/libraries/TransactionHelper.sol";
import "@openzeppelin/contracts/interfaces/IERC1271.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@matterlabs/zksync-contracts/l2/system-contracts/Constants.sol";
import "@matterlabs/zksync-contracts/l2/system-contracts/libraries/SystemContractsCaller.sol";
import "@matterlabs/zksync-contracts/l2/system-contracts/libraries/Utils.sol";
import "./interfaces/ISubscriptionManager.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract SubscriptionAccount is IAccount, IERC1271 {
    using TransactionHelper for Transaction;

    uint256 public constant ONE_DAY = 24 hours;
    bytes4 constant EIP1271_SUCCESS_RETURN_VALUE = 0x1626ba7e;

    struct Limit {
        uint256 limitUSD;
        uint256 availableUSD;
        uint256 resetTime;
        bool isEnabled;
    }

    mapping(address => Limit) public limits;
    address public owner;
    ISubscriptionManager public subscriptionManager;
    AggregatorV3Interface internal priceFeed;

    error InvalidAmount();
    error InvalidUpdate();
    error InvalidNonce();
    error InvalidSignature();
    error InsufficientBalance();
    error ExceededDailySpendingLimit();
    error SubscriptionPaymentFailed();
    error TransactionExecutionFailed();
    error NotSubscribed();

    event SpendingLimitSet(address indexed token, uint256 amountUSD);
    event SpendingLimitRemoved(address indexed token);
    event SubscriptionFeePaid(uint256 amount);

    constructor(
        address _owner,
        address _subscriptionManagerAddress,
        address _priceFeedAddress
    ) {
        owner = _owner;
        subscriptionManager = ISubscriptionManager(_subscriptionManagerAddress);
        priceFeed = AggregatorV3Interface(_priceFeedAddress);
    }

    modifier onlyBootloader() {
        require(
            msg.sender == BOOTLOADER_FORMAL_ADDRESS,
            "Only bootloader can call this function"
        );
        _;
    }

    modifier onlyAccount() {
        require(
            msg.sender == address(this),
            "Only the account itself can call this function"
        );
        _;
    }

    modifier onlySubscriptionManager() {
        require(
            msg.sender == address(subscriptionManager),
            "Only subscription manager can charge the wallet"
        );
        _;
    }

    function setSpendingLimit(
        address _token,
        uint256 _amountUSD
    ) public onlyAccount {
        if (_amountUSD == 0) revert InvalidAmount();

        Limit storage limit = limits[_token];
        uint256 timestamp = block.timestamp;

        if (limit.isEnabled) {
            if (timestamp > limit.resetTime) {
                limit.resetTime = timestamp + ONE_DAY;
                limit.availableUSD = _amountUSD;
                limit.limitUSD = _amountUSD;
            } else {
                revert InvalidUpdate();
            }
        } else {
            limit.limitUSD = _amountUSD;
            limit.availableUSD = _amountUSD;
            limit.resetTime = timestamp + ONE_DAY;
            limit.isEnabled = true;
        }

        emit SpendingLimitSet(_token, _amountUSD);
    }

    function removeSpendingLimit(address _token) public onlyAccount {
        if (!isValidUpdate(_token)) revert InvalidUpdate();
        Limit storage limit = limits[_token];
        limit.isEnabled = false;
        emit SpendingLimitRemoved(_token);
    }

    function isValidUpdate(address _token) internal view returns (bool) {
        if (limits[_token].isEnabled) {
            return block.timestamp > limits[_token].resetTime;
        } else {
            return true;
        }
    }

    function _updateLimit(
        address _token,
        uint256 _limitUSD,
        uint256 _availableUSD,
        uint256 _resetTime,
        bool _isEnabled
    ) private {
        Limit storage limit = limits[_token];
        limit.limitUSD = _limitUSD;
        limit.availableUSD = _availableUSD;
        limit.resetTime = _resetTime;
        limit.isEnabled = _isEnabled;
    }

    function _checkSpendingLimit(address _token, uint256 _amountWei) internal {
        Limit memory limit = limits[_token];

        if (!limit.isEnabled) return;

        uint256 timestamp = block.timestamp;
        uint256 amountUSD = convertETHtoUSD(_amountWei);

        if (timestamp > limit.resetTime) {
            limit.resetTime = timestamp + ONE_DAY;
            limit.availableUSD = limit.limitUSD;
        }

        if (limit.availableUSD < amountUSD) revert ExceededDailySpendingLimit();

        limit.availableUSD -= amountUSD;
        limits[_token] = limit;
    }

    function validateTransaction(
        bytes32,
        bytes32 _suggestedSignedHash,
        Transaction calldata _transaction
    ) external payable override onlyBootloader returns (bytes4 magic) {
        return _validateTransaction(_suggestedSignedHash, _transaction);
    }

    function _validateTransaction(
        bytes32 _suggestedSignedHash,
        Transaction calldata _transaction
    ) internal returns (bytes4 magic) {
        SystemContractsCaller.systemCallWithPropagatedRevert(
            uint32(gasleft()),
            address(NONCE_HOLDER_SYSTEM_CONTRACT),
            0,
            abi.encodeCall(
                INonceHolder.incrementMinNonceIfEquals,
                (_transaction.nonce)
            )
        );

        bytes32 txHash;
        if (_suggestedSignedHash == bytes32(0)) {
            txHash = _transaction.encodeHash();
        } else {
            txHash = _suggestedSignedHash;
        }

        uint256 requiredBalance = _transaction.totalRequiredBalance();
        require(
            address(this).balance >= requiredBalance,
            "Insufficient balance"
        );

        if (
            isValidSignature(txHash, _transaction.signature) ==
            EIP1271_SUCCESS_RETURN_VALUE
        ) {
            magic = ACCOUNT_VALIDATION_SUCCESS_MAGIC;
        } else {
            magic = bytes4(0);
        }
    }

    function executeTransaction(
        bytes32,
        bytes32,
        Transaction calldata _transaction
    ) external payable override onlyBootloader {
        _executeTransaction(_transaction);
    }

    function _executeTransaction(Transaction calldata _transaction) internal {
        address to = address(uint160(_transaction.to));
        uint128 value = Utils.safeCastToU128(_transaction.value);
        bytes memory data = _transaction.data;

        // Call SpendLimit contract to ensure that ETH `value` doesn't exceed the daily spending limit
        if (value > 0) {
            _checkSpendingLimit(address(ETH_TOKEN_SYSTEM_CONTRACT), value);
        }

        if (to == address(DEPLOYER_SYSTEM_CONTRACT)) {
            uint32 gas = Utils.safeCastToU32(gasleft());

            // Note, that the deployer contract can only be called
            // with a "systemCall" flag.
            SystemContractsCaller.systemCallWithPropagatedRevert(
                gas,
                to,
                value,
                data
            );
        } else {
            bool success;
            assembly {
                success := call(
                    gas(),
                    to,
                    value,
                    add(data, 0x20),
                    mload(data),
                    0,
                    0
                )
            }
            require(success);
        }
    }

    function isValidSignature(
        bytes32 _hash,
        bytes memory _signature
    ) public view override returns (bytes4 magic) {
        magic = EIP1271_SUCCESS_RETURN_VALUE;

        if (_signature.length == 65) {
            bytes32 r;
            bytes32 s;
            uint8 v;
            assembly {
                r := mload(add(_signature, 0x20))
                s := mload(add(_signature, 0x40))
                v := byte(0, mload(add(_signature, 0x60)))
            }
            if (v < 27) {
                v += 27;
            }
            if (v != 27 && v != 28) {
                magic = bytes4(0);
            } else if (
                uint256(s) >
                0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0
            ) {
                magic = bytes4(0);
            } else {
                address signer = ecrecover(_hash, v, r, s);
                if (signer == owner) {
                    magic = EIP1271_SUCCESS_RETURN_VALUE;
                } else {
                    magic = bytes4(0);
                }
            }
        } else {
            magic = bytes4(0);
        }
    }

    function payForTransaction(
        bytes32,
        bytes32,
        Transaction calldata _transaction
    ) external payable override onlyBootloader {
        bool success = _transaction.payToTheBootloader();
        if (!success) revert TransactionExecutionFailed();
    }

    function prepareForPaymaster(
        bytes32,
        bytes32,
        Transaction calldata _transaction
    ) external payable override onlyBootloader {
        _transaction.processPaymasterInput();
    }

    function executeTransactionFromOutside(
        Transaction calldata _transaction
    ) external payable onlyAccount {
        _validateTransaction(bytes32(0), _transaction);
        _executeTransaction(_transaction);
    }

    function convertUSDtoETH(uint256 amountUSD) public view returns (uint256) {
        uint256 ethPrice = getLatestPrice();
        uint256 amountWei = (amountUSD * 1e18) / ethPrice;
        return amountWei;
    }

    function convertETHtoUSD(uint256 amountWei) public view returns (uint256) {
        uint256 ethPrice = getLatestPrice();
        uint256 amountUSD = (amountWei * ethPrice) / 1e18;
        return amountUSD;
    }

    function getLatestPrice() public view returns (uint256) {
        (, int price, , , ) = priceFeed.latestRoundData();
        return uint256(price);
    }

    function chargeWallet(uint256 amount) external onlySubscriptionManager {
        _checkSpendingLimit(address(ETH_TOKEN_SYSTEM_CONTRACT), amount);

        (bool success, ) = address(subscriptionManager).call{value: amount}("");
        require(success, "Transfer to subscription manager failed");
    }

    fallback() external {
        assert(msg.sender != BOOTLOADER_FORMAL_ADDRESS);
    }

    function withdraw(uint256 _amount) public onlyAccount {
        require(address(this).balance >= _amount, "Insufficient balance");
        payable(owner).transfer(_amount);
    }

    receive() external payable {}
}
