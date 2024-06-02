// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SubscriptionManager.sol";
import "@matterlabs/zksync-contracts/l2/system-contracts/Constants.sol";
import "@matterlabs/zksync-contracts/l2/system-contracts/libraries/SystemContractsCaller.sol";

/**
 * @title ManagerFactory
 * @dev This contract is responsible for deploying SubscriptionManager contracts.
 */
contract ManagerFactory {
    // Event to notify when a new SubscriptionManager is deployed
    event ManagerDeployed(
        address indexed owner,
        address indexed manager,
        string name
    );

    bytes32 public managerBytecodeHash;
    mapping(address => address[]) public ownerToManagers;

    /**
     * @dev Constructor to initialize the factory with the bytecode hash of the SubscriptionManager.
     * @param _managerBytecodeHash The bytecode hash of the SubscriptionManager contract.
     */
    constructor(bytes32 _managerBytecodeHash) {
        managerBytecodeHash = _managerBytecodeHash;
    }

    /**
     * @dev Deploy a new SubscriptionManager contract using system contract.
     * @param salt The salt value for creating the contract address.
     * @param owner The owner of the SubscriptionManager contract.
     * @param priceFeedAddress The address of the Chainlink price feed contract.
     * @param name The name of the SubscriptionManager contract.
     * @return managerAddress The address of the deployed SubscriptionManager contract.
     */
    function deployManager(
        bytes32 salt,
        address owner,
        address priceFeedAddress,
        string calldata name
    ) external returns (address managerAddress) {
        bytes memory constructorArgs = abi.encode(
            owner,
            priceFeedAddress,
            name
        );

        (bool success, bytes memory returnData) = SystemContractsCaller
            .systemCallWithReturndata(
                uint32(gasleft()),
                address(DEPLOYER_SYSTEM_CONTRACT),
                uint128(0),
                abi.encodeCall(
                    DEPLOYER_SYSTEM_CONTRACT.create2,
                    (salt, managerBytecodeHash, constructorArgs)
                )
            );
        require(success, "Deployment failed");

        (managerAddress) = abi.decode(returnData, (address));

        ownerToManagers[owner].push(managerAddress);
        emit ManagerDeployed(owner, managerAddress, name);
    }

    /**
     * @dev Get all SubscriptionManager addresses deployed by a specific owner.
     * @param owner The address of the owner.
     * @return An array of SubscriptionManager addresses.
     */
    function getManagersByOwner(
        address owner
    ) external view returns (address[] memory) {
        return ownerToManagers[owner];
    }
}
