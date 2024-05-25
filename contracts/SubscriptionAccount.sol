// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IAccount.sol";
import "@matterlabs/zksync-contracts/l2/system-contracts/libraries/TransactionHelper.sol";
import "@openzeppelin/contracts/interfaces/IERC1271.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@matterlabs/zksync-contracts/l2/system-contracts/Constants.sol";
import "./interfaces/ISubscriptionManager.sol";

/**
 * @title SubscriptionAccount
 * @dev This contract represents a subscription account that can execute transactions with spending limits.
 * It interacts with a subscription manager to handle subscription payments and renewals.
 */
contract SubscriptionAccount is IAccount, IERC1271 {
    using TransactionHelper for Transaction;

    uint256 public constant ONE_DAY = 24 hours; // The duration of one day in seconds
    bytes4 constant EIP1271_SUCCESS_RETURN_VALUE = 0x1626ba7e;

    struct Limit {
        uint256 limit; // The maximum spending limit for a token
        uint256 available; // The available spending amount for a token
        uint256 resetTime; // The timestamp when the spending limit resets
        bool isEnabled; // Flag indicating if the spending limit is enabled
    }

    mapping(address => Limit) public limits; // Mapping to store spending limits for each token

    address public owner; // The owner of the subscription account
    ISubscriptionManager public subscriptionManager; // The subscription manager contract

    // Custom errors
    error InvalidAmount();
    error InvalidUpdate();
    error InvalidNonce();
    error InvalidSignature();
    error InsufficientBalance();
    error ExceededDailySpendingLimit();
    error SubscriptionPaymentFailed();
    error TransactionExecutionFailed();
    error NotSubscribed();

    // Events
    event SpendingLimitSet(address indexed token, uint256 amount);
    event SpendingLimitRemoved(address indexed token);
    event SubscriptionFeePaid(uint256 amount);

    /**
     * @dev Constructor function to initialize the subscription account.
     * @param _owner The address of the account owner.
     * @param _subscriptionManagerAddress The address of the subscription manager contract.
     */
    constructor(address _owner, address _subscriptionManagerAddress) {
        owner = _owner;
        subscriptionManager = ISubscriptionManager(_subscriptionManagerAddress);
    }

    /**
     * @dev Modifier to restrict access to only the bootloader.
     */
    modifier onlyBootloader() {
        require(
            msg.sender == BOOTLOADER_FORMAL_ADDRESS,
            "Only bootloader can call this function"
        );
        _;
    }

    /**
     * @dev Set the spending limit for a specific token.
     * @param _token The address of the token.
     * @param _amount The spending limit amount.
     */
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

    /**
     * @dev Remove the spending limit for a specific token.
     * @param _token The address of the token.
     */
    function removeSpendingLimit(address _token) public {
        if (!isValidUpdate(_token)) revert InvalidUpdate();
        _updateLimit(_token, 0, 0, 0, false);
        emit SpendingLimitRemoved(_token);
    }

    /**
     * @dev Check if an update to the spending limit is valid.
     * @param _token The address of the token.
     * @return A boolean indicating if the update is valid.
     */
    function isValidUpdate(address _token) internal view returns (bool) {
        if (limits[_token].isEnabled) {
            return (limits[_token].limit == limits[_token].available ||
                block.timestamp > limits[_token].resetTime);
        } else {
            return false;
        }
    }

    /**
     * @dev Update the spending limit for a token.
     * @param _token The address of the token.
     * @param _limit The new spending limit.
     * @param _available The new available spending amount.
     * @param _resetTime The new reset timestamp.
     * @param _isEnabled The new enabled status.
     */
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

    /**
     * @dev Check the spending limit before executing a transaction.
     * @param _token The address of the token.
     * @param _amount The amount to be spent.
     */
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

    /**
     * @dev Validate a transaction.
     * @param _suggestedSignedHash The suggested signed hash of the transaction.
     * @param _transaction The transaction to be validated.
     * @return magic The magic value indicating the validation status.
     */
    function validateTransaction(
        bytes32,
        bytes32 _suggestedSignedHash,
        Transaction calldata _transaction
    ) external payable override onlyBootloader returns (bytes4 magic) {
        return _validateTransaction(_suggestedSignedHash, _transaction);
    }

    /**
     * @dev Internal function to validate a transaction.
     * @param _suggestedSignedHash The suggested signed hash of the transaction.
     * @param _transaction The transaction to be validated.
     * @return magic The magic value indicating the validation status.
     */
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

    /**
     * @dev Execute a transaction.
     * @param _transaction The transaction to be executed.
     */
    function executeTransaction(
        bytes32,
        bytes32,
        Transaction calldata _transaction
    ) external payable override onlyBootloader {
        _executeTransaction(_transaction);
    }

    /**
     * @dev Internal function to execute a transaction.
     * @param _transaction The transaction to be executed.
     */
    function _executeTransaction(Transaction calldata _transaction) internal {
        address to = address(uint160(_transaction.to));
        uint256 value = _transaction.reserved[1];
        bytes memory data = _transaction.data;

        if (to == address(subscriptionManager)) {
            uint256 planId = abi.decode(data, (uint256));
            _paySubscriptionFee(planId);
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
            require(success, "Transaction execution failed");
        }
    }

    function _paySubscriptionFee(uint256 planId) internal {
        uint256 subscriptionFeeUSD = subscriptionManager.getSubscriptionFee(
            planId
        );
        uint256 subscriptionFeeWei = subscriptionManager.convertUSDtoETH(
            subscriptionFeeUSD
        );

        if (address(this).balance < subscriptionFeeWei)
            revert InsufficientBalance();

        (bool success, ) = address(subscriptionManager).call{
            value: subscriptionFeeWei
        }(
            abi.encodeWithSignature(
                "processSubscriptionPayment(address,uint256)",
                address(this),
                planId
            )
        );
        if (!success) revert SubscriptionPaymentFailed();

        emit SubscriptionFeePaid(subscriptionFeeWei);
    }

    /**
     * @dev Check if a signature is valid for the given hash.
     * @param _hash The hash to be signed.
     * @param _signature The signature to be verified.
     * @return magic The magic value indicating the signature validity.
     */
    function isValidSignature(
        bytes32 _hash,
        bytes memory _signature
    ) public view override returns (bytes4 magic) {
        magic = EIP1271_SUCCESS_RETURN_VALUE;

        if (_signature.length == 65) {
            // ECDSA signature
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
            // Invalid signature length
            magic = bytes4(0);
        }
    }

    /**
     * @dev Pay for a transaction.
     * @param _transaction The transaction to be paid for.
     */
    function payForTransaction(
        bytes32,
        bytes32,
        Transaction calldata _transaction
    ) external payable override onlyBootloader {
        bool success = _transaction.payToTheBootloader();
        if (!success) revert TransactionExecutionFailed();
    }

    /**
     * @dev Prepare for a paymaster (not used in this example).
     */
    function prepareForPaymaster(
        bytes32,
        bytes32,
        Transaction calldata _transaction
    ) external payable override onlyBootloader {
        // This function is part of the IAccount interface but is not used in this example.
    }

    /**
     * @dev Execute a transaction from outside the account.
     * @param _transaction The transaction to be executed.
     */
    function executeTransactionFromOutside(
        Transaction calldata _transaction
    ) external payable {
        _validateTransaction(bytes32(0), _transaction);
        _executeTransaction(_transaction);
    }

    fallback() external {
        // fallback of default account shouldn't be called by bootloader under no circumstances
        assert(msg.sender != BOOTLOADER_FORMAL_ADDRESS);

        // If the contract is called directly, behave like an EOA
    }

    receive() external payable {}
}
