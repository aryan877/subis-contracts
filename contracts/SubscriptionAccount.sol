// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IAccount.sol";
import "@matterlabs/zksync-contracts/l2/system-contracts/libraries/TransactionHelper.sol";
import "@openzeppelin/contracts/interfaces/IERC1271.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@matterlabs/zksync-contracts/l2/system-contracts/Constants.sol";
import "./interfaces/ISubscriptionManager.sol";

contract SubscriptionAccount is IAccount, IERC1271 {
    using TransactionHelper for Transaction;

    uint256 public constant ONE_DAY = 24 hours;
    bytes4 constant EIP1271_SUCCESS_RETURN_VALUE = 0x1626ba7e;

    struct Limit {
        uint256 limit;
        uint256 available;
        uint256 resetTime;
        bool isEnabled;
    }

    mapping(address => Limit) public limits;
    address public owner;
    ISubscriptionManager public subscriptionManager;

    error InvalidAmount();
    error InvalidUpdate();
    error InvalidNonce();
    error InvalidSignature();
    error InsufficientBalance();
    error ExceededDailySpendingLimit();
    error SubscriptionPaymentFailed();
    error TransactionExecutionFailed();
    error NotSubscribed();

    event SpendingLimitSet(address indexed token, uint256 amount);
    event SpendingLimitRemoved(address indexed token);
    event SubscriptionFeePaid(uint256 amount);

    constructor(address _owner, address _subscriptionManagerAddress) {
        owner = _owner;
        subscriptionManager = ISubscriptionManager(_subscriptionManagerAddress);
    }

    modifier onlyBootloader() {
        require(
            msg.sender == BOOTLOADER_FORMAL_ADDRESS,
            "Only bootloader can call this function"
        );
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not the owner");
        _;
    }

    function setSpendingLimit(address _token, uint256 _amount) public {
        if (_amount == 0) revert InvalidAmount();

        uint256 resetTime;
        uint256 timestamp = block.timestamp;

        if (isValidUpdate(_token)) {
            resetTime = timestamp + ONE_DAY;
        } else {
            resetTime = timestamp;
        }

        _updateLimit(_token, _amount, _amount, resetTime, true);
        emit SpendingLimitSet(_token, _amount);
    }

    function removeSpendingLimit(address _token) public {
        if (!isValidUpdate(_token)) revert InvalidUpdate();
        _updateLimit(_token, 0, 0, 0, false);
        emit SpendingLimitRemoved(_token);
    }

    function isValidUpdate(address _token) internal view returns (bool) {
        if (limits[_token].isEnabled) {
            return (limits[_token].limit == limits[_token].available ||
                block.timestamp > limits[_token].resetTime);
        } else {
            return false;
        }
    }

    function _updateLimit(
        address _token,
        uint256 _limit,
        uint256 _available,
        uint256 _resetTime,
        bool _isEnabled
    ) private {
        Limit storage limit = limits[_token];
        limit.limit = _limit;
        limit.available = _available;
        limit.resetTime = _resetTime;
        limit.isEnabled = _isEnabled;
    }

    function _checkSpendingLimit(address _token, uint256 _amount) internal {
        Limit memory limit = limits[_token];

        if (!limit.isEnabled) return;

        uint256 timestamp = block.timestamp;

        if (limit.limit != limit.available && timestamp > limit.resetTime) {
            limit.resetTime = timestamp + ONE_DAY;
            limit.available = limit.limit;
        } else if (limit.limit == limit.available) {
            limit.resetTime = timestamp + ONE_DAY;
        }

        if (limit.available < _amount) revert ExceededDailySpendingLimit();

        limit.available -= _amount;
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

        if (_transaction.reserved[1] > 0) {
            _checkSpendingLimit(address(0), _transaction.reserved[1]);
        }

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
        uint256 value = _transaction.reserved[1];
        bytes memory data = _transaction.data;

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
        require(success, "Transaction execution failed");
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
    ) external payable {
        _validateTransaction(bytes32(0), _transaction);
        _executeTransaction(_transaction);
    }

    function chargeWallet(uint256 amount) external {
        require(
            msg.sender == address(subscriptionManager),
            "Only subscription manager can charge the wallet"
        );
        require(
            address(this).balance >= amount,
            "Insufficient balance in the wallet"
        );

        (bool success, ) = address(subscriptionManager).call{value: amount}("");
        require(success, "Transfer to subscription manager failed");
    }

    function withdraw(uint256 amount) external onlyOwner {
        require(
            address(this).balance >= amount,
            "Insufficient balance in the wallet"
        );

        (bool success, ) = owner.call{value: amount}("");
        require(success, "Withdrawal failed");
    }

    fallback() external {
        assert(msg.sender != BOOTLOADER_FORMAL_ADDRESS);
    }

    receive() external payable {}
}
