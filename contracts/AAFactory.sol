// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@matterlabs/zksync-contracts/l2/system-contracts/Constants.sol";
import "@matterlabs/zksync-contracts/l2/system-contracts/libraries/SystemContractsCaller.sol";

/**
 * @title AAFactory
 * @dev This contract is responsible for deploying subscription accounts.
 */
contract AAFactory {
    bytes32 public aaBytecodeHash;
    mapping(address => mapping(address => address))
        public ownerToManagerToAccount;

    // Event
    event AccountDeployed(
        address indexed account,
        address indexed owner,
        address indexed manager
    );

    /**
     * @dev Constructor function to initialize the factory.
     * @param _aaBytecodeHash The bytecode hash of the subscription account contract.
     */
    constructor(bytes32 _aaBytecodeHash) {
        aaBytecodeHash = _aaBytecodeHash;
    }

    /**
     * @dev Deploy a new subscription account.
     * @param salt The salt value for creating the account address.
     * @param owner The owner of the subscription account.
     * @param subscriptionManager The address of the subscription manager contract.
     * @return accountAddress The address of the deployed subscription account.
     */
    function deployAccount(
        bytes32 salt,
        address owner,
        address subscriptionManager
    ) external returns (address accountAddress) {
        (bool success, bytes memory returnData) = SystemContractsCaller
            .systemCallWithReturndata(
                uint32(gasleft()),
                address(DEPLOYER_SYSTEM_CONTRACT),
                uint128(0),
                abi.encodeCall(
                    DEPLOYER_SYSTEM_CONTRACT.create2Account,
                    (
                        salt,
                        aaBytecodeHash,
                        abi.encode(owner, subscriptionManager),
                        IContractDeployer.AccountAbstractionVersion.Version1
                    )
                )
            );
        require(success, "Deployment failed");
        (accountAddress) = abi.decode(returnData, (address));

        ownerToManagerToAccount[owner][subscriptionManager] = accountAddress;

        emit AccountDeployed(accountAddress, owner, subscriptionManager);
    }

    /**
     * @dev Get the deployed subscription account address for a specific owner and manager.
     * @param owner The address of the owner.
     * @param subscriptionManager The address of the subscription manager contract.
     * @return The deployed subscription account address, or address(0) if not found.
     */
    function getAccountByOwnerAndManager(
        address owner,
        address subscriptionManager
    ) external view returns (address) {
        return ownerToManagerToAccount[owner][subscriptionManager];
    }
}
