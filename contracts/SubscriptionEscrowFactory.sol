// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@matterlabs/zksync-contracts/l2/system-contracts/Constants.sol";
import "@matterlabs/zksync-contracts/l2/system-contracts/libraries/SystemContractsCaller.sol";

contract SubscriptionEscrowFactory {
    event SubscriptionEscrowCreated(
        address indexed escrowAddress,
        address indexed owner,
        uint256 subscriptionCancelPeriod,
        uint256 escrowDisputePeriod,
        uint256 subscriptionRenewalWindowStart,
        uint256 subscriptionRenewalWindowEnd
    );

    bytes32 public escrowBytecodeHash;

    constructor(bytes32 _escrowBytecodeHash) {
        escrowBytecodeHash = _escrowBytecodeHash;
    }

    function deploySubscriptionEscrow(
        bytes32 salt,
        address _owner,
        uint256 _subscriptionCancelPeriod,
        uint256 _escrowDisputePeriod,
        uint256 _subscriptionRenewalWindowStart,
        uint256 _subscriptionRenewalWindowEnd
    ) external returns (address escrowAddress) {
        (bool success, bytes memory returnData) = SystemContractsCaller
            .systemCallWithReturndata(
                uint32(gasleft()),
                address(DEPLOYER_SYSTEM_CONTRACT),
                uint128(0),
                abi.encodeCall(
                    DEPLOYER_SYSTEM_CONTRACT.create2Account,
                    (
                        salt,
                        escrowBytecodeHash,
                        abi.encode(
                            _owner,
                            _subscriptionCancelPeriod,
                            _escrowDisputePeriod,
                            _subscriptionRenewalWindowStart,
                            _subscriptionRenewalWindowEnd
                        ),
                        IContractDeployer.AccountAbstractionVersion.Version1
                    )
                )
            );
        if (!success) {
            // Decode the error message from the returnData
            string memory errorMessage = abi.decode(returnData, (string));
            revert(
                string(abi.encodePacked("Deployment failed: ", errorMessage))
            );
        }
        escrowAddress = abi.decode(returnData, (address));
        emit SubscriptionEscrowCreated(
            escrowAddress,
            _owner,
            _subscriptionCancelPeriod,
            _escrowDisputePeriod,
            _subscriptionRenewalWindowStart,
            _subscriptionRenewalWindowEnd
        );
    }
}
