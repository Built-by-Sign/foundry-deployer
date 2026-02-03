// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IVersionable
 * @dev Interface for contracts that expose a version string for upgrade compatibility checks.
 */
interface IVersionable {
    function version() external view returns (string memory);
}
