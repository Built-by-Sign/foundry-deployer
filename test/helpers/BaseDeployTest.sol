// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Versionable} from "../../src/Versionable.sol";
import {Ownable} from "solady/auth/Ownable.sol";

/**
 * @title BaseDeployTest
 * @notice Base contract with common test utilities and mock contracts
 * @dev Inherit from this in test files to avoid duplicating mock contract patterns
 */
abstract contract BaseDeployTest is Test {
    /**
     * @notice Common initialization function for mock contracts with Ownable
     * @param contractAddress Address of the contract to initialize
     * @param owner Owner address to set
     * @dev Standardized pattern to replace duplicated initializeOwner calls
     *      Note: Contracts must expose an initializeOwner(address) function
     */
    function initializeContractOwner(address contractAddress, address owner) internal {
        require(Ownable(contractAddress).owner() == address(0), "Already initialized");
        // Call the contract's initializeOwner function
        (bool success,) = contractAddress.call(abi.encodeWithSignature("initializeOwner(address)", owner));
        require(success, "initializeOwner call failed");
    }

    /**
     * @notice Helper to check if a contract has an owner set
     * @param contractAddress Address to check
     * @return True if owner is set (non-zero)
     */
    function hasOwner(address contractAddress) internal view returns (bool) {
        return Ownable(contractAddress).owner() != address(0);
    }

    /**
     * @notice Helper to verify contract ownership
     * @param contractAddress Contract to check
     * @param expectedOwner Expected owner address
     */
    function assertOwner(address contractAddress, address expectedOwner) internal view {
        assertEq(Ownable(contractAddress).owner(), expectedOwner, "Contract owner does not match expected owner");
    }
}

/**
 * @title BaseMockContract
 * @notice Base contract for mock contracts with common patterns
 * @dev Use this as a base for test mock contracts to reduce duplication
 */
abstract contract BaseMockContract is Versionable, Ownable {
    uint256 public value;

    constructor(string memory evmSuffix_) Versionable(evmSuffix_) {
        // Don't initialize owner here - will be initialized after deployment
    }

    function initializeOwner(address _owner) external {
        require(owner() == address(0), "Already initialized");
        _initializeOwner(_owner);
    }

    function setValue(uint256 _value) external onlyOwner {
        value = _value;
    }
}
