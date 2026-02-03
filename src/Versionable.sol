// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IVersionable} from "./interfaces/IVersionable.sol";

/**
 * @title Versionable
 * @notice Abstract contract for versioning with optional EVM suffix
 * @dev Provides version() implementation that combines base version with EVM suffix
 */
abstract contract Versionable is IVersionable {
    /// @notice EVM version suffix (e.g., "", "-shanghai", "-cancun")
    /// @dev Set via constructor parameter, typically from EVM_SUFFIX env var
    /// Note: Cannot use immutable for strings in Solidity < 0.8.22
    string private _evmSuffix;

    /**
     * @notice Constructor
     * @param evmSuffix_ The EVM version suffix to append to version string
     */
    constructor(string memory evmSuffix_) {
        _evmSuffix = evmSuffix_;
    }

    /**
     * @notice Returns the base version string without EVM suffix
     * @dev Must be overridden to return format: "{major}.{minor}.{patch}-{ContractName}".
     *      Contract names must not contain hyphens, as the first hyphen after the semver separates the name.
     * @return Base version string (e.g., "1.0.0-MyContract")
     */
    function _baseVersion() internal pure virtual returns (string memory);

    /**
     * @notice Returns the full version string including EVM suffix
     * @return Complete version string (e.g., "1.0.0-MyContract-cancun")
     */
    function version() external view returns (string memory) {
        return string.concat(_baseVersion(), _evmSuffix);
    }
}
