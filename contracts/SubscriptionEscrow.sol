// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@matterlabs/zksync-contracts/l2/system-contracts/Constants.sol";
import "@matterlabs/zksync-contracts/l2/system-contracts/libraries/TransactionHelper.sol";
import "@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IAccount.sol";
import "@openzeppelin/contracts/interfaces/IERC1271.sol";
import "@matterlabs/zksync-contracts/l2/system-contracts/libraries/SystemContractsCaller.sol";

contract SubscriptionEscrow is IAccount, ReentrancyGuard, IERC1271 {
    using TransactionHelper for Transaction;

    error InvalidOwnerAddress();
    error InvalidSubscriptionCancelPeriod();
    error InvalidEscrowDisputePeriod();
    error InvalidSubscriptionRenewalWindowStart();
    error InvalidSubscriptionRenewalWindowEnd();

    struct Subscription {
        uint256 price;
        uint256 period;
        uint256 startTime;
        uint256 endTime;
        bool active;
        uint256 lastPaymentTime;
        uint256 cumulativePaid;
        address[] allowedPaymasters;
    }

    struct Escrow {
        address seller;
        address buyer;
        uint256 amount;
        bool released;
        uint256 disputeDeadline;
        bool disputed;
        address disputeWinner;
    }

    bytes4 constant EIP1271_SUCCESS_RETURN_VALUE = 0x1626ba7e;

    // Chainlink price feed aggregators for different currency pairs
    mapping(bytes32 => AggregatorV3Interface) public priceFeeds;
    uint256 public constant DECIMALS = 18;
    uint256 public subscriptionCounter;
    uint256 public escrowCounter;
    uint256 public subscriptionCancelPeriod;
    uint256 public escrowDisputePeriod;
    uint256 public subscriptionRenewalWindowStart;
    uint256 public subscriptionRenewalWindowEnd;

    mapping(uint256 => Subscription) public subscriptions;
    mapping(address => uint256[]) public userSubscriptions;
    mapping(uint256 => Escrow) public escrows;

    address public owner;

    event SubscriptionCreated(
        uint256 indexed subscriptionId,
        address indexed user,
        uint256 price,
        uint256 period
    );
    event SubscriptionRenewed(
        uint256 indexed subscriptionId,
        address indexed user,
        uint256 newEndTime
    );
    event SubscriptionCancelled(
        uint256 indexed subscriptionId,
        address indexed user,
        uint256 refundAmount
    );
    event SubscriptionPaymentMade(
        uint256 indexed subscriptionId,
        address indexed user,
        uint256 paymentAmount
    );
    event EscrowCreated(
        uint256 indexed escrowId,
        address indexed seller,
        address indexed buyer,
        uint256 amount
    );
    event EscrowReleased(
        uint256 indexed escrowId,
        address indexed seller,
        address indexed buyer,
        uint256 amount
    );
    event EscrowDisputed(uint256 indexed escrowId, address indexed disputer);
    event EscrowDisputeResolved(
        uint256 indexed escrowId,
        address indexed winner,
        uint256 amount
    );

    constructor(
        address _owner,
        uint256 _subscriptionCancelPeriod,
        uint256 _escrowDisputePeriod,
        uint256 _subscriptionRenewalWindowStart,
        uint256 _subscriptionRenewalWindowEnd
    ) {
        if (_owner == address(0)) {
            revert InvalidOwnerAddress();
        }
        if (_subscriptionCancelPeriod == 0) {
            revert InvalidSubscriptionCancelPeriod();
        }
        if (_escrowDisputePeriod == 0) {
            revert InvalidEscrowDisputePeriod();
        }
        if (
            _subscriptionRenewalWindowStart == 0 ||
            _subscriptionRenewalWindowStart >= _subscriptionRenewalWindowEnd
        ) {
            revert InvalidSubscriptionRenewalWindowStart();
        }
        if (_subscriptionRenewalWindowEnd == 0) {
            revert InvalidSubscriptionRenewalWindowEnd();
        }

        owner = _owner;
        subscriptionCancelPeriod = _subscriptionCancelPeriod;
        escrowDisputePeriod = _escrowDisputePeriod;
        subscriptionRenewalWindowStart = _subscriptionRenewalWindowStart;
        subscriptionRenewalWindowEnd = _subscriptionRenewalWindowEnd;
        // Initialize Chainlink price feed aggregators for different currency pairs
        priceFeeds["ETH/USD"] = AggregatorV3Interface(
            0xfEefF7c3fB57d18C5C6Cdd71e45D2D0b4F9377bF
        );
        priceFeeds["DAI/USD"] = AggregatorV3Interface(
            0x3aE81863E2F4cdea95b0c96E9C3C71cf1e10EFFE
        );
        priceFeeds["USDC/USD"] = AggregatorV3Interface(
            0x1844478CA634f3a762a2E71E3386837Bd50C947F
        );
    }

    modifier onlyBootloader() {
        require(
            msg.sender == BOOTLOADER_FORMAL_ADDRESS,
            "Only bootloader can call this method"
        );
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this method");
        _;
    }

    // Native Account Abstraction: Validate the transaction
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
        // Incrementing the nonce of the account.
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

        uint256 totalRequiredBalance = _transaction.totalRequiredBalance();
        require(
            totalRequiredBalance <= address(this).balance,
            "Not enough balance for fee + value"
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

    // Native Account Abstraction: Execute the transaction
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

        if (to == address(DEPLOYER_SYSTEM_CONTRACT)) {
            uint32 gas = Utils.safeCastToU32(gasleft());
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

    // Function to execute transaction from outside the bootloader
    function executeTransactionFromOutside(
        Transaction calldata _transaction
    ) external payable override {
        bytes4 magic = _validateTransaction(bytes32(0), _transaction);
        require(magic == ACCOUNT_VALIDATION_SUCCESS_MAGIC, "NOT VALIDATED");

        _executeTransaction(_transaction);
    }

    // Native Account Abstraction: Check if the signature is valid (EIP-1271)
    function isValidSignature(
        bytes32 _hash,
        bytes memory _signature
    ) public view override returns (bytes4 magic) {
        magic = EIP1271_SUCCESS_RETURN_VALUE;

        if (_signature.length != 65) {
            magic = bytes4(0);
        }

        uint8 v;
        bytes32 r;
        bytes32 s;

        assembly {
            r := mload(add(_signature, 0x20))
            s := mload(add(_signature, 0x40))
            v := and(mload(add(_signature, 0x41)), 0xff)
        }

        if (v != 27 && v != 28) {
            magic = bytes4(0);
        }

        if (
            uint256(s) >
            0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0
        ) {
            magic = bytes4(0);
        }

        address recoveredAddress = ecrecover(_hash, v, r, s);

        if (recoveredAddress != owner && recoveredAddress != address(0)) {
            magic = bytes4(0);
        }
    }

    function payForTransaction(
        bytes32,
        bytes32,
        Transaction calldata _transaction
    ) external payable override onlyBootloader {
        bool success = _transaction.payToTheBootloader();
        require(success, "Failed to pay the fee to the operator");
    }

    function prepareForPaymaster(
        bytes32,
        bytes32,
        Transaction calldata _transaction
    ) external payable override onlyBootloader {
        _transaction.processPaymasterInput();
    }

    // Chainlink Price Feed: Get the latest subscription price in the specified currency
    function getSubscriptionPrice(
        uint256 _subscriptionId,
        bytes32 _currency
    ) public view returns (uint256) {
        Subscription storage subscription = subscriptions[_subscriptionId];
        require(subscription.active, "Subscription not active");

        AggregatorV3Interface priceFeed = priceFeeds[_currency];
        require(address(priceFeed) != address(0), "Invalid currency");

        (, int256 price, , , ) = priceFeed.latestRoundData();
        uint256 priceInCurrency = uint256(price);

        return
            (subscription.price * priceInCurrency) / 10 ** priceFeed.decimals();
    }

    // Create a new subscription with the specified price, period, and allowed paymasters
    function createSubscription(
        uint256 _price,
        uint256 _period,
        address[] memory _allowedPaymasters
    ) external {
        require(_price > 0, "Invalid subscription price");
        require(_period > 0, "Invalid subscription period");

        uint256 subscriptionId = subscriptionCounter++;
        subscriptions[subscriptionId] = Subscription({
            price: _price,
            period: _period,
            startTime: block.timestamp,
            endTime: block.timestamp + _period,
            active: true,
            lastPaymentTime: block.timestamp,
            cumulativePaid: 0,
            allowedPaymasters: _allowedPaymasters
        });
        userSubscriptions[msg.sender].push(subscriptionId);

        emit SubscriptionCreated(subscriptionId, msg.sender, _price, _period);
    }

    // Renew an existing subscription by paying the required amount in the specified currency
    function renewSubscription(
        uint256 _subscriptionId,
        bytes32 _currency
    ) external payable {
        Subscription storage subscription = subscriptions[_subscriptionId];
        require(subscription.active, "Subscription not active");

        uint256 currentTime = block.timestamp;
        require(
            currentTime >=
                subscription.endTime - subscriptionRenewalWindowStart &&
                currentTime <=
                subscription.endTime - subscriptionRenewalWindowEnd,
            "Renewal window not open"
        );

        uint256 paymentAmount = getSubscriptionPrice(
            _subscriptionId,
            _currency
        );
        require(msg.value >= paymentAmount, "Insufficient payment");

        subscription.endTime += subscription.period;
        subscription.lastPaymentTime = block.timestamp;
        subscription.cumulativePaid += paymentAmount;

        emit SubscriptionRenewed(
            _subscriptionId,
            msg.sender,
            subscription.endTime
        );
    }

    // Cancel an active subscription and issue a refund based on the remaining time
    function cancelSubscription(uint256 _subscriptionId) external {
        Subscription storage subscription = subscriptions[_subscriptionId];
        require(subscription.active, "Subscription not active");
        require(
            block.timestamp < subscription.endTime - subscriptionCancelPeriod,
            "Cannot cancel within cancel period"
        );

        subscription.active = false;
        uint256 refundAmount = ((subscription.endTime - block.timestamp) *
            subscription.price) / subscription.period;

        (bool success, ) = payable(msg.sender).call{value: refundAmount}("");
        require(success, "Failed to transfer refund");

        emit SubscriptionCancelled(_subscriptionId, msg.sender, refundAmount);
    }

    // Make a subscription payment using the specified paymaster and currency
    function makeSubscriptionPayment(
        uint256 _subscriptionId,
        address _paymaster,
        bytes32 _currency
    ) external payable {
        Subscription storage subscription = subscriptions[_subscriptionId];
        require(subscription.active, "Subscription not active");
        require(
            isAllowedPaymaster(_subscriptionId, _paymaster),
            "Paymaster not allowed"
        );

        uint256 paymentAmount = getSubscriptionPrice(
            _subscriptionId,
            _currency
        );
        require(msg.value >= paymentAmount, "Insufficient payment");

        subscription.lastPaymentTime = block.timestamp;
        subscription.cumulativePaid += paymentAmount;

        emit SubscriptionPaymentMade(
            _subscriptionId,
            msg.sender,
            paymentAmount
        );
    }

    // Check if a paymaster is allowed for a specific subscription
    function isAllowedPaymaster(
        uint256 _subscriptionId,
        address _paymaster
    ) public view returns (bool) {
        Subscription storage subscription = subscriptions[_subscriptionId];
        for (uint256 i = 0; i < subscription.allowedPaymasters.length; i++) {
            if (subscription.allowedPaymasters[i] == _paymaster) {
                return true;
            }
        }
        return false;
    }

    // Create a new escrow between a seller and a buyer with the specified amount
    function createEscrow(address _seller) external payable {
        require(msg.value > 0, "Escrow amount must be greater than zero");

        uint256 escrowId = escrowCounter++;
        escrows[escrowId] = Escrow({
            seller: _seller,
            buyer: msg.sender,
            amount: msg.value,
            released: false,
            disputeDeadline: block.timestamp + escrowDisputePeriod,
            disputed: false,
            disputeWinner: address(0)
        });

        emit EscrowCreated(escrowId, _seller, msg.sender, msg.value);
    }

    // Release the escrow funds to the seller if the conditions are met
    function releaseEscrow(uint256 _escrowId) external nonReentrant {
        Escrow storage escrow = escrows[_escrowId];
        require(escrow.buyer == msg.sender, "Only buyer can release escrow");
        require(!escrow.released, "Escrow already released");
        require(!escrow.disputed, "Escrow is disputed");

        escrow.released = true;

        (bool success, ) = payable(escrow.seller).call{value: escrow.amount}(
            ""
        );
        require(success, "Failed to transfer escrow amount");

        emit EscrowReleased(
            _escrowId,
            escrow.seller,
            escrow.buyer,
            escrow.amount
        );
    }

    // Dispute an escrow if there is a disagreement between the buyer and seller
    function disputeEscrow(uint256 _escrowId) external nonReentrant {
        Escrow storage escrow = escrows[_escrowId];
        require(
            msg.sender == escrow.buyer || msg.sender == escrow.seller,
            "Only buyer or seller can dispute"
        );
        require(!escrow.released, "Escrow already released");
        require(
            block.timestamp <= escrow.disputeDeadline,
            "Dispute deadline has passed"
        );
        escrow.disputed = true;

        emit EscrowDisputed(_escrowId, msg.sender);
    }

    // Resolve a disputed escrow by specifying the winner
    function resolveEscrowDispute(
        uint256 _escrowId,
        address _winner
    ) external onlyOwner nonReentrant {
        Escrow storage escrow = escrows[_escrowId];
        require(escrow.disputed, "Escrow is not disputed");
        require(!escrow.released, "Escrow already released");

        escrow.disputeWinner = _winner;
        escrow.released = true;

        (bool success, ) = payable(_winner).call{value: escrow.amount}("");
        require(success, "Failed to transfer dispute amount");

        emit EscrowDisputeResolved(_escrowId, _winner, escrow.amount);
    }

    // Update the owner of the contract
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner cannot be the zero address");
        owner = newOwner;
    }

    // Fallback functions
    fallback() external payable {
        assert(msg.sender != BOOTLOADER_FORMAL_ADDRESS);
    }

    receive() external payable {}
}
