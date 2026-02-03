// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Versionable} from "src/Versionable.sol";

/// @title VersionableImplementation
/// @notice Concrete implementation of Versionable for testing
contract VersionableImplementation is Versionable {
    string private constant BASE_VERSION = "1.0.0-TestContract";

    constructor(string memory evmSuffix_) Versionable(evmSuffix_) {}

    function _baseVersion() internal pure override returns (string memory) {
        return BASE_VERSION;
    }
}

/// @title VersionableTest
/// @notice Comprehensive unit tests for Versionable contract
contract VersionableTest is Test {
    VersionableImplementation public versionable;
    VersionableImplementation public versionableWithSuffix;

    function setUp() public {
        versionable = new VersionableImplementation("");
        versionableWithSuffix = new VersionableImplementation("-cancun");
    }

    function test_Version_NoSuffix() public view {
        assertEq(versionable.version(), "1.0.0-TestContract");
    }

    function test_Version_WithSuffix() public view {
        assertEq(versionableWithSuffix.version(), "1.0.0-TestContract-cancun");
    }

    function test_Version_DifferentSuffixes() public {
        VersionableImplementation shanghai = new VersionableImplementation("-shanghai");
        VersionableImplementation paris = new VersionableImplementation("-paris");
        VersionableImplementation london = new VersionableImplementation("-london");

        assertEq(shanghai.version(), "1.0.0-TestContract-shanghai");
        assertEq(paris.version(), "1.0.0-TestContract-paris");
        assertEq(london.version(), "1.0.0-TestContract-london");
    }

    function test_Version_Persistence() public view {
        assertEq(versionable.version(), "1.0.0-TestContract");
        assertEq(versionable.version(), "1.0.0-TestContract");
        assertEq(versionable.version(), "1.0.0-TestContract");
    }

    function test_Version_MultipleImplementations() public {
        VersionableImplementation v1 = new VersionableImplementation("");
        VersionableImplementation v2 = new VersionableImplementation("-cancun");
        VersionableImplementation v3 = new VersionableImplementation("-shanghai");

        assertEq(v1.version(), "1.0.0-TestContract");
        assertEq(v2.version(), "1.0.0-TestContract-cancun");
        assertEq(v3.version(), "1.0.0-TestContract-shanghai");
    }

    function test_Version_EmptySuffix() public view {
        assertEq(versionable.version(), "1.0.0-TestContract");
    }

    function test_Version_LongSuffix() public {
        string memory longSuffix = "-very-long-evm-suffix-for-testing-purposes-that-exceeds-normal-length";
        VersionableImplementation longSuf = new VersionableImplementation(longSuffix);
        assertEq(longSuf.version(), string.concat("1.0.0-TestContract", longSuffix));
    }

    function test_Version_ConcatenationCorrectness() public {
        string memory base = "1.0.0-TestContract";
        string memory suffix = "-cancun";
        VersionableImplementation v = new VersionableImplementation(suffix);

        assertEq(v.version(), string.concat(base, suffix));
    }

    function test_Version_SuffixImmutability() public view {
        // EVM suffix is set in constructor and cannot be changed
        assertEq(versionableWithSuffix.version(), "1.0.0-TestContract-cancun");

        // Multiple calls should return same value
        for (uint256 i = 0; i < 5; i++) {
            assertEq(versionableWithSuffix.version(), "1.0.0-TestContract-cancun");
        }
    }

    function testFuzz_Version_RandomSuffix(string memory randomSuffix) public {
        string memory base = "1.0.0-TestContract";
        VersionableImplementation v = new VersionableImplementation(randomSuffix);
        assertEq(v.version(), string.concat(base, randomSuffix));
    }

    function test_Version_GasCost() public view {
        uint256 gasBefore = gasleft();
        versionable.version();
        uint256 gasUsed = gasBefore - gasleft();

        // version() should be reasonably cheap (< 10k gas)
        // Includes string concatenation and storage reads
        assertLt(gasUsed, 10000);
    }

    function test_Version_UnicodeSuffix() public {
        VersionableImplementation unicodeVer = new VersionableImplementation(unicode"-α-evm");
        assertEq(unicodeVer.version(), unicode"1.0.0-TestContract-α-evm");
    }

    function test_Version_SpecialCharsSuffix() public {
        VersionableImplementation special = new VersionableImplementation("-evm_v2.0");
        assertEq(special.version(), "1.0.0-TestContract-evm_v2.0");
    }

    function test_Version_RealWorldFormat() public view {
        assertEq(versionable.version(), "1.0.0-TestContract");
    }

    function test_Version_RealWorldWithEVM() public view {
        assertEq(versionableWithSuffix.version(), "1.0.0-TestContract-cancun");
    }

    function test_Version_SuffixIndependence() public {
        VersionableImplementation v1 = new VersionableImplementation("");
        VersionableImplementation v2 = new VersionableImplementation("-cancun");
        VersionableImplementation v3 = new VersionableImplementation("-shanghai");

        // All should have same base, different full versions
        string memory base = "1.0.0-TestContract";
        assertTrue(_startsWith(v1.version(), base));
        assertTrue(_startsWith(v2.version(), base));
        assertTrue(_startsWith(v3.version(), base));

        assertEq(v1.version(), base);
        assertEq(v2.version(), string.concat(base, "-cancun"));
        assertEq(v3.version(), string.concat(base, "-shanghai"));
    }

    function test_Version_Length() public view {
        string memory v1 = versionable.version();
        string memory v2 = versionableWithSuffix.version();

        // v2 should be longer than v1 by the suffix length
        assertGt(bytes(v2).length, bytes(v1).length);
        assertEq(bytes(v2).length, bytes(v1).length + bytes("-cancun").length);
    }

    function test_Version_MultipleSuffixFormats() public {
        VersionableImplementation noPrefix = new VersionableImplementation("cancun");
        VersionableImplementation withPrefix = new VersionableImplementation("-cancun");
        VersionableImplementation withUnderscore = new VersionableImplementation("_cancun");

        assertEq(noPrefix.version(), "1.0.0-TestContractcancun");
        assertEq(withPrefix.version(), "1.0.0-TestContract-cancun");
        assertEq(withUnderscore.version(), "1.0.0-TestContract_cancun");
    }

    function test_Version_BaseVersionConstant() public {
        // Multiple instances should have same base
        VersionableImplementation v1 = new VersionableImplementation("");
        VersionableImplementation v2 = new VersionableImplementation("");

        assertEq(v1.version(), v2.version());
    }

    function test_Version_ValidStringOutput() public view {
        string memory ver = versionable.version();

        // Should not be empty
        assertGt(bytes(ver).length, 0);

        // Should be a valid string (doesn't revert)
        bytes memory verBytes = bytes(ver);
        assertEq(verBytes.length, bytes("1.0.0-TestContract").length);
    }

    function test_Version_MaxSuffixLength() public {
        string memory maxSuffix = string.concat("-", _repeat("evm", 50));
        VersionableImplementation maxVer = new VersionableImplementation(maxSuffix);

        string memory expected = string.concat("1.0.0-TestContract", maxSuffix);
        assertEq(maxVer.version(), expected);
    }

    function test_Version_Comparison() public {
        VersionableImplementation v1 = new VersionableImplementation("");
        VersionableImplementation v2 = new VersionableImplementation("");
        VersionableImplementation v3 = new VersionableImplementation("-cancun");

        // v1 and v2 should be equal
        assertEq(v1.version(), v2.version());

        // v1 and v3 should be different
        assertNotEq(v1.version(), v3.version());
    }

    /// @notice Helper: Check if string starts with prefix
    function _startsWith(string memory str, string memory prefix) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory prefixBytes = bytes(prefix);

        if (strBytes.length < prefixBytes.length) {
            return false;
        }

        for (uint256 i = 0; i < prefixBytes.length; i++) {
            if (strBytes[i] != prefixBytes[i]) {
                return false;
            }
        }

        return true;
    }

    /// @notice Helper: Repeat a string n times
    function _repeat(string memory str, uint256 times) internal pure returns (string memory) {
        string memory result = "";
        for (uint256 i = 0; i < times; i++) {
            result = string.concat(result, str);
        }
        return result;
    }
}
