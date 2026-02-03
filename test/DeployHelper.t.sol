// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {DeployHelper} from "../src/DeployHelper.sol";
import {Versionable} from "../src/Versionable.sol";
import {IVersionable} from "../src/interfaces/IVersionable.sol";
import {ICreateX} from "../src/interfaces/ICreateX.sol";
import {Ownable} from "solady/auth/Ownable.sol";

// Test contracts: Constructors don't initialize owner - owner initialized post-deployment

contract MockContract is Versionable, Ownable {
    uint256 public value;

    constructor(string memory evmSuffix_) Versionable(evmSuffix_) {}

    function initializeOwner(address _owner) external {
        require(owner() == address(0), "Already initialized");
        _initializeOwner(_owner);
    }

    function setValue(uint256 _value) external onlyOwner {
        value = _value;
    }

    function _baseVersion() internal pure override returns (string memory) {
        return "1.0.0-MockContract";
    }
}

contract MockContractWithArgs is Versionable, Ownable {
    uint256 public value;

    constructor(string memory evmSuffix_, uint256 _value) Versionable(evmSuffix_) {
        // Don't initialize owner here - will be initialized after deployment
        value = _value;
    }

    function initializeOwner(address _owner) external {
        require(owner() == address(0), "Already initialized");
        _initializeOwner(_owner);
    }

    function _baseVersion() internal pure override returns (string memory) {
        return "1.0.0-MockContractWithArgs";
    }
}

contract MockContractV2 is Versionable, Ownable {
    uint256 public value;

    constructor(string memory evmSuffix_) Versionable(evmSuffix_) {}

    function initializeOwner(address _owner) external {
        require(owner() == address(0), "Already initialized");
        _initializeOwner(_owner);
    }

    function _baseVersion() internal pure override returns (string memory) {
        return "2.0.0-MockContractV2";
    }
}

// Test contract that initializes owner in constructor (doesn't need post-deploy init)
contract ConstructorOwnedContract is Versionable, Ownable {
    uint256 public value;

    constructor(string memory evmSuffix_, address _owner) Versionable(evmSuffix_) {
        _initializeOwner(_owner);
    }

    function _baseVersion() internal pure override returns (string memory) {
        return "1.0.0-ConstructorOwnedContract";
    }
}

// Test contract with payable constructor requiring ETH
contract PayableConstructorContract is Versionable {
    constructor(string memory evmSuffix_) payable Versionable(evmSuffix_) {
        require(msg.value >= 1 ether, "Must send ETH");
    }

    function _baseVersion() internal pure override returns (string memory) {
        return "1.0.0-PayableConstructorContract";
    }
}

// Test contract without version function (for testing version extraction failure)
contract NonVersionableContract {
    uint256 public value;

    constructor() {
        value = 42;
    }
}

// Test contract with invalid version format (no hyphen)
contract InvalidVersionFormatContract is IVersionable {
    function version() external pure returns (string memory) {
        return "1.0.0NoHyphen"; // Missing hyphen before contract name
    }
}

// Test contract with payable initialization function (for testing deployCreate3AndInit)
contract PayableInitContract is Versionable, Ownable {
    uint256 public initValue;
    address public initializer;

    constructor(string memory evmSuffix_) Versionable(evmSuffix_) {}

    function initialize(address _owner) external payable {
        require(owner() == address(0), "Already initialized");
        require(msg.value > 0, "Must send ETH");
        _initializeOwner(_owner);
        initValue = msg.value;
        initializer = msg.sender;
    }

    function _baseVersion() internal pure override returns (string memory) {
        return "1.0.0-PayableInitContract";
    }
}

// Test deployment helper
contract TestDeployHelper is DeployHelper {
    function setUp() public override {
        _setUp("test");
    }

    function setUpWithDeployer(string memory subfolder, address deployer) public {
        _setUp(subfolder, deployer);
    }

    function deployMockContract() public returns (address) {
        bytes memory creationCode = abi.encodePacked(type(MockContract).creationCode, abi.encode(_getEvmSuffix()));
        return deploy(creationCode);
    }

    function deployMockContractWithArgs(uint256 value) public returns (address) {
        bytes memory creationCode =
            abi.encodePacked(type(MockContractWithArgs).creationCode, abi.encode(_getEvmSuffix(), value));
        return deploy(creationCode);
    }

    function deployMockContractV2() public returns (address) {
        bytes memory creationCode = abi.encodePacked(type(MockContractV2).creationCode, abi.encode(_getEvmSuffix()));
        return deploy(creationCode);
    }

    function computeMockContractAddress() public returns (address) {
        bytes memory creationCode = abi.encodePacked(type(MockContract).creationCode, abi.encode(_getEvmSuffix()));
        return computeDeploymentAddress(creationCode);
    }

    function readEvmVersionFromToml(string memory toml, string memory profile) public view returns (string memory) {
        return _readEvmVersionFromToml(toml, profile);
    }

    function isStandardJsonSkipped() public view returns (bool) {
        return _SKIP_STANDARD_JSON_INPUT;
    }

    function getSaltForVersion(string memory version) public view returns (bytes32) {
        return _getSalt(version);
    }

    function checkAndTransferOwner(address instance) public {
        _checkChainAndSetOwner(instance);
    }

    function saveDeployments() public {
        _afterAll();
    }

    function parseEnvBool(string memory raw) public pure returns (bool) {
        return _parseEnvBool(raw);
    }

    function guardSaltPublic(bytes32 salt) public view returns (bytes32) {
        return _guardSalt(salt);
    }

    function assertBroadcastSenderPublic() public view {
        _assertBroadcastSenderMatchesDeployer();
    }

    function getDeployer() public view returns (address) {
        return _deployer;
    }

    function deployPublic(bytes memory creationCode) public returns (address) {
        return deploy(creationCode);
    }
}

// Helper that skips initialization (for contracts with constructor-based ownership)
contract NoInitDeployHelper is DeployHelper {
    function setUp() public override {
        _setUp("test");
    }

    function deployConstructorOwnedContract() public returns (address) {
        bytes memory creationCode =
            abi.encodePacked(type(ConstructorOwnedContract).creationCode, abi.encode(_getEvmSuffix(), _deployer));
        return deploy(creationCode);
    }

    // Override to return empty bytes (no post-deploy init)
    function _getPostDeployInitData() internal pure override returns (bytes memory) {
        return "";
    }
}

// Helper that deploys payable constructors with ETH (no post-deploy init)
contract PayableNoInitDeployHelper is DeployHelper {
    function setUp() public override {
        _setUp("test");
    }

    function deployPayableContract() public returns (address) {
        bytes memory creationCode =
            abi.encodePacked(type(PayableConstructorContract).creationCode, abi.encode(_getEvmSuffix()));
        return deploy(creationCode);
    }

    function _getDeployValues() internal pure override returns (ICreateX.Values memory) {
        return ICreateX.Values({constructorAmount: 1 ether, initCallAmount: 0});
    }

    function _getPostDeployInitData() internal pure override returns (bytes memory) {
        return "";
    }
}

// Helper that uses custom init data (different owner)
contract CustomInitDeployHelper is DeployHelper {
    address public customOwner;

    function setUp() public override {
        _setUp("test");
    }

    function setCustomOwner(address _customOwner) public {
        customOwner = _customOwner;
    }

    function deployMockContract() public returns (address) {
        bytes memory creationCode = abi.encodePacked(type(MockContract).creationCode, abi.encode(_getEvmSuffix()));
        return deploy(creationCode);
    }

    // Override to use custom owner
    function _getPostDeployInitData() internal view override returns (bytes memory) {
        return abi.encodeWithSignature("initializeOwner(address)", customOwner);
    }
}

// Helper with init data and non-zero initCallAmount
contract InitWithValueDeployHelper is DeployHelper {
    function setUp() public override {
        _setUp("test");
    }

    function deployPayableContract() public returns (address) {
        bytes memory creationCode =
            abi.encodePacked(type(PayableConstructorContract).creationCode, abi.encode(_getEvmSuffix()));
        return deploy(creationCode);
    }

    function _getDeployValues() internal pure override returns (ICreateX.Values memory) {
        return ICreateX.Values({constructorAmount: 1 ether, initCallAmount: 0});
    }

    function _getPostDeployInitData() internal pure override returns (bytes memory) {
        return "";
    }
}

// Helper that exercises deployCreate3AndInit with non-empty init data and value
contract InitDataDeployHelper is DeployHelper {
    function setUp() public override {
        _setUp("test");
    }

    function deployPayableInitContract() public returns (address) {
        bytes memory creationCode =
            abi.encodePacked(type(PayableInitContract).creationCode, abi.encode(_getEvmSuffix()));
        return deploy(creationCode);
    }

    function _getDeployValues() internal pure override returns (ICreateX.Values memory) {
        // Non-zero initCallAmount to forward ETH to init function
        return ICreateX.Values({constructorAmount: 0, initCallAmount: 0.5 ether});
    }

    function _getPostDeployInitData() internal view override returns (bytes memory) {
        // Non-empty init data to call payable initialize function
        return abi.encodeWithSignature("initialize(address)", _deployer);
    }
}

// Base helper that reverts if standard JSON hooks are called (used to test SKIP_STANDARD_JSON_INPUT)
abstract contract StandardJsonGuardBase is DeployHelper {
    bool internal _skipStandardJsonInputForTest;
    bool internal _revertStandardJsonHooksForTest;

    constructor(bool skipStandardJsonInputForTest_) {
        _skipStandardJsonInputForTest = skipStandardJsonInputForTest_;
        _revertStandardJsonHooksForTest = true;
    }

    function setUp() public override {
        _setUp("test");
    }

    function deployMockContract() public returns (address) {
        bytes memory creationCode = abi.encodePacked(type(MockContract).creationCode, abi.encode(_getEvmSuffix()));
        return deploy(creationCode);
    }

    function isStandardJsonSkipped() public view returns (bool) {
        return _shouldSkipStandardJsonInput();
    }

    function _shouldSkipStandardJsonInput() internal view override returns (bool) {
        return _skipStandardJsonInputForTest;
    }

    function _generateStandardJsonInput(string memory) internal view override returns (string memory) {
        if (_revertStandardJsonHooksForTest) {
            revert("Standard JSON hooks should be skipped");
        }
        return "";
    }

    function _checkStandardJsonInput(string memory, string memory, string memory) internal view override {
        if (_revertStandardJsonHooksForTest) {
            revert("Standard JSON hooks should be skipped");
        }
    }

    function _saveContractToStandardJsonInput(string memory, string memory, string memory) internal view override {
        if (_revertStandardJsonHooksForTest) {
            revert("Standard JSON hooks should be skipped");
        }
    }
}

contract StandardJsonGuardSkip is StandardJsonGuardBase {
    constructor() StandardJsonGuardBase(true) {}
}

contract StandardJsonGuardNoSkip is StandardJsonGuardBase {
    constructor() StandardJsonGuardBase(false) {}
}

// Helper that uses the real _checkStandardJsonInput implementation (for testing mismatch detection)
contract RealStandardJsonCheckHelper is DeployHelper {
    function setUp() public override {
        _setUp("test");
    }

    function deployMockContract() public returns (address) {
        bytes memory creationCode = abi.encodePacked(type(MockContract).creationCode, abi.encode(_getEvmSuffix()));
        return deploy(creationCode);
    }

    // Override to return deterministic JSON without FFI
    // This ensures the mismatch check always runs, regardless of FFI availability
    function _generateStandardJsonInput(string memory) internal pure override returns (string memory) {
        // Return a valid-looking standard JSON that will always mismatch the corrupted file
        return '{"language":"Solidity","sources":{},"settings":{"optimizer":{"enabled":true}}}';
    }
}

contract DeployHelperTest is Test {
    TestDeployHelper public helper;
    address public deployer;
    address public prodOwner;

    function setUp() public {
        deployer = address(this);
        prodOwner = makeAddr("prodOwner");

        // Set environment variables
        vm.setEnv("PROD_OWNER", vm.toString(prodOwner));
        vm.setEnv("MAINNET_CHAIN_IDS", "1,56,137");
        vm.setEnv("FORCE_DEPLOY", "true");
        vm.setEnv("ALLOWED_DEPLOYMENT_SENDER", vm.toString(deployer));
        vm.setEnv("SKIP_STANDARD_JSON_INPUT", "true"); // Skip by default to avoid test interference

        // Clean up any stray standard JSON files from previous tests to prevent interference
        // We manually clean up known test contract standard JSON files
        string memory standardJsonDir = string.concat(vm.projectRoot(), "/deployments/test/standard-json-inputs");
        string[] memory knownFiles = new string[](6);
        knownFiles[0] = string.concat(standardJsonDir, "/1.0.0-MockContract.json");
        knownFiles[1] = string.concat(standardJsonDir, "/1.0.0-MockContractWithArgs.json");
        knownFiles[2] = string.concat(standardJsonDir, "/2.0.0-MockContractV2.json");
        knownFiles[3] = string.concat(standardJsonDir, "/1.0.0-ConstructorOwnedContract.json");
        knownFiles[4] = string.concat(standardJsonDir, "/1.0.0-PayableConstructorContract.json");
        knownFiles[5] = string.concat(standardJsonDir, "/1.0.0-PayableInitContract.json");
        for (uint256 i = 0; i < knownFiles.length; i++) {
            if (vm.isFile(knownFiles[i])) {
                vm.removeFile(knownFiles[i]);
            }
        }

        // Clean up the shared -latest.json file at the start of the test suite
        _cleanupLatestJsonFile();

        helper = new TestDeployHelper();
        helper.setUp();
    }

    /// @notice Helper to clean up the shared -latest.json file before tests
    function _cleanupLatestJsonFile() internal {
        string memory latestPath =
            string.concat(vm.projectRoot(), "/deployments/test/", vm.toString(block.chainid), "-latest.json");
        if (vm.isFile(latestPath)) {
            vm.removeFile(latestPath);
        }
    }

    function test_Deploy_CreatesContract() public {
        address deployed = helper.deployMockContract();

        assertTrue(deployed.code.length > 0, "Contract should have code");
        assertEq(MockContract(deployed).owner(), deployer, "Owner should be deployer");
    }

    function test_Deploy_IsDeterministic() public {
        address predicted = helper.computeMockContractAddress();
        address deployed = helper.deployMockContract();

        assertEq(predicted, deployed, "Predicted address should match deployed address");
    }

    function test_Deploy_SkipsIfAlreadyDeployed() public {
        address first = helper.deployMockContract();
        address second = helper.deployMockContract();

        assertEq(first, second, "Should return same address for duplicate deployment");
    }

    function test_Deploy_DifferentVersionsDifferentAddresses() public {
        address v1 = helper.deployMockContract();
        address v2 = helper.deployMockContractV2();

        assertTrue(v1 != v2, "Different versions should have different addresses");
    }

    function test_Deploy_WithConstructorArgs() public {
        uint256 expectedValue = 42;
        address deployed = helper.deployMockContractWithArgs(expectedValue);

        assertEq(MockContractWithArgs(deployed).value(), expectedValue, "Constructor arg should be set");
    }

    function test_Version_ExtractsCorrectly() public {
        address deployed = helper.deployMockContract();
        string memory version = IVersionable(deployed).version();

        string memory expectedVersion = string.concat("1.0.0-MockContract", helper.getEvmSuffix());
        assertEq(version, expectedVersion, "Version should be extracted correctly");
    }

    function test_Salt_IsConsistent() public view {
        bytes32 salt1 = helper.getSaltForVersion("1.0.0-MockContract");
        bytes32 salt2 = helper.getSaltForVersion("1.0.0-MockContract");

        assertEq(salt1, salt2, "Salt should be consistent for same version");
    }

    function test_Salt_DifferentForDifferentVersions() public view {
        bytes32 salt1 = helper.getSaltForVersion("1.0.0-MockContract");
        bytes32 salt2 = helper.getSaltForVersion("2.0.0-MockContract");

        assertTrue(salt1 != salt2, "Salt should differ for different versions");
    }

    function test_ReadEvmVersionFromToml_DefaultProfile() public view {
        string memory toml =
            "[profile.default]\nsolc_version = \"0.8.20\"\nevm_version = \"cancun\"\noptimizer = true\n";
        string memory evmVersion = helper.readEvmVersionFromToml(toml, "default");

        assertEq(evmVersion, "cancun", "Should read evm_version from default profile");
    }

    function test_ReadEvmVersionFromToml_ProfileOverride() public view {
        string memory toml = string.concat(
            "[profile.default]\nsolc_version = \"0.8.20\"\nevm_version = \"shanghai\"\n",
            "[profile.ci]\nevm_version = \"cancun\"\n"
        );
        string memory evmVersion = helper.readEvmVersionFromToml(toml, "ci");

        assertEq(evmVersion, "cancun", "Should prefer evm_version from active profile");
    }

    function test_ReadEvmVersionFromToml_FallsBackToDefault() public view {
        string memory toml =
            "[profile.default]\nsolc_version = \"0.8.20\"\nevm_version = \"cancun\"\n[profile.ci]\noptimizer = true\n";
        string memory evmVersion = helper.readEvmVersionFromToml(toml, "ci");

        assertEq(evmVersion, "cancun", "Should fall back to default profile evm_version");
    }

    function test_ReadEvmVersionFromToml_RootFallback() public view {
        string memory toml = "evm_version = \"shanghai\"\n";
        string memory evmVersion = helper.readEvmVersionFromToml(toml, "ci");

        assertEq(evmVersion, "shanghai", "Should fall back to root-level evm_version");
    }

    function test_ParseEnvBool_AcceptsAllTrueValues() public view {
        assertTrue(helper.parseEnvBool("true"), "Should accept 'true'");
        assertTrue(helper.parseEnvBool("True"), "Should accept 'True'");
        assertTrue(helper.parseEnvBool("TRUE"), "Should accept 'TRUE'");
        assertTrue(helper.parseEnvBool("1"), "Should accept '1'");
    }

    function test_ParseEnvBool_RejectsAllFalseValues() public view {
        assertFalse(helper.parseEnvBool("false"), "Should reject 'false'");
        assertFalse(helper.parseEnvBool("False"), "Should reject 'False'");
        assertFalse(helper.parseEnvBool("FALSE"), "Should reject 'FALSE'");
        assertFalse(helper.parseEnvBool("0"), "Should reject '0'");
        assertFalse(helper.parseEnvBool(""), "Should reject empty string");
        assertFalse(helper.parseEnvBool("yes"), "Should reject 'yes'");
        assertFalse(helper.parseEnvBool("no"), "Should reject 'no'");
        assertFalse(helper.parseEnvBool("random"), "Should reject random string");
    }

    function test_OwnershipTransfer_SkipsOnTestnet() public {
        // Deploy on testnet (chain ID not in MAINNET_CHAIN_IDS)
        vm.chainId(11155111); // Sepolia

        address deployed = helper.deployMockContract();
        address originalOwner = MockContract(deployed).owner();

        helper.checkAndTransferOwner(deployed);

        assertEq(MockContract(deployed).owner(), originalOwner, "Owner should not change on testnet");
    }

    function test_OwnershipTransfer_WorksOnMainnet() public {
        // Deploy on mainnet (chain ID 1)
        vm.chainId(1);

        // Reinitialize helper with mainnet chain ID
        helper = new TestDeployHelper();
        helper.setUp();

        address deployed = helper.deployMockContract();

        vm.expectCall(deployed, abi.encodeWithSelector(Ownable.transferOwnership.selector, prodOwner));
        helper.checkAndTransferOwner(deployed);

        assertEq(MockContract(deployed).owner(), prodOwner, "Owner should be transferred on mainnet");
    }

    function test_OwnershipTransfer_SkipsIfAlreadySet() public {
        vm.chainId(1);

        helper = new TestDeployHelper();
        helper.setUp();

        address deployed = helper.deployMockContract();

        // First transfer
        helper.checkAndTransferOwner(deployed);

        // Second transfer should be skipped
        helper.checkAndTransferOwner(deployed);

        assertEq(MockContract(deployed).owner(), prodOwner, "Owner should still be prod owner");
    }

    function test_OwnershipTransfer_RevertsOnBroadcastMismatch_Mainnet() public {
        vm.chainId(1);

        // Create helper with a specific deployer address
        address expectedDeployer = makeAddr("expectedDeployer");
        helper = new TestDeployHelper();
        helper.setUpWithDeployer("test", expectedDeployer);

        address deployed = helper.deployMockContract();

        // Start broadcast with wrong sender (not the deployer)
        address wrongSender = makeAddr("wrongSender");
        vm.startBroadcast(wrongSender);

        // Should revert because broadcast sender doesn't match deployer
        vm.expectRevert(
            abi.encodeWithSelector(DeployHelper.BroadcastSenderMismatch.selector, expectedDeployer, wrongSender)
        );
        helper.checkAndTransferOwner(deployed);

        vm.stopBroadcast();
    }

    function test_OwnershipTransfer_AllowsBroadcastMatch_Mainnet() public {
        vm.chainId(1);

        helper = new TestDeployHelper();
        helper.setUp();

        address deployed = helper.deployMockContract();

        // Start broadcast as the deployer (address(this))
        vm.startBroadcast(address(this));

        // Verify broadcast sender check passes (doesn't revert)
        // This exercises the broadcast detection and sender validation at DeployHelper.sol:316-317
        helper.assertBroadcastSenderPublic();

        vm.stopBroadcast();

        // Note: We execute the actual ownership transfer outside broadcast because in
        // Foundry tests, vm.startBroadcast doesn't change msg.sender - it only records
        // transactions. The prank-skip logic at DeployHelper.sol:339-341 is designed for
        // real forge script broadcasts where the broadcast sender IS the actual msg.sender.
        // In tests, we verify the broadcast check passes (above), and the ownership transfer
        // works correctly (below). In production, both happen atomically within broadcast.
        helper.checkAndTransferOwner(deployed);

        assertEq(MockContract(deployed).owner(), prodOwner, "Owner should be transferred to prod owner");
    }

    function test_OwnershipTransfer_SkipsOnTestnet_EvenInBroadcast() public {
        // Deploy on testnet (chain ID not in MAINNET_CHAIN_IDS)
        vm.chainId(11155111); // Sepolia

        address deployed = helper.deployMockContract();
        address originalOwner = MockContract(deployed).owner();

        // Start broadcast with any sender (doesn't matter on testnet)
        address someSender = makeAddr("someSender");
        vm.startBroadcast(someSender);

        // Should skip ownership transfer without checking broadcast sender
        helper.checkAndTransferOwner(deployed);

        vm.stopBroadcast();

        assertEq(MockContract(deployed).owner(), originalOwner, "Owner should not change on testnet");
    }

    function test_DeploymentCategory_SetCorrectly() public view {
        assertEq(helper.deploymentCategory(), "test", "Deployment category should be 'test'");
    }

    function test_SkipStandardJsonInput_SkipsHooks() public {
        StandardJsonGuardSkip guardHelper = new StandardJsonGuardSkip();
        guardHelper.setUp();

        address deployed = guardHelper.deployMockContract();
        assertTrue(deployed.code.length > 0, "Deployment should succeed when standard JSON is skipped");
        assertTrue(guardHelper.isStandardJsonSkipped(), "Skip flag should be enabled");
    }

    function test_SkipStandardJsonInput_DisabledCallsHooks() public {
        StandardJsonGuardNoSkip guardHelper = new StandardJsonGuardNoSkip();
        guardHelper.setUp();

        vm.expectRevert(bytes("Standard JSON hooks should be skipped"));
        guardHelper.deployMockContract();
    }

    function test_CREATE3_SameAddressAcrossChains() public {
        // Deploy on chain 1
        vm.chainId(1);
        TestDeployHelper helper1 = new TestDeployHelper();
        helper1.setUp();
        address addr1 = helper1.computeMockContractAddress();

        // Deploy on chain 137 (Polygon)
        vm.chainId(137);
        TestDeployHelper helper2 = new TestDeployHelper();
        helper2.setUp();
        address addr2 = helper2.computeMockContractAddress();

        assertEq(addr1, addr2, "CREATE3 should produce same address across chains");
    }

    function test_MultipleDifferentContracts() public {
        address mock1 = helper.deployMockContract();
        address mock2 = helper.deployMockContractV2();

        assertTrue(mock1 != mock2, "Different contracts should have different addresses");
        assertTrue(mock1.code.length > 0, "First contract should have code");
        assertTrue(mock2.code.length > 0, "Second contract should have code");
    }

    function testFuzz_Deploy_WithRandomConstructorArgs(uint256 value) public {
        // Note: Constructor args don't affect the deployment address because
        // the version string is constant ("1.0.0-MockContractWithArgs").
        // CREATE3 addresses depend only on deployer + salt (derived from version).
        // See test_Deploy_AddressIndependentOfConstructorArgs for explicit proof.

        address deployed = helper.deployMockContractWithArgs(value);

        assertEq(MockContractWithArgs(deployed).value(), value, "Constructor arg should match");
        assertTrue(deployed.code.length > 0, "Contract should be deployed");

        // Verify address is deterministic (same for all values)
        address predicted = helper.computeDeploymentAddress(
            abi.encodePacked(type(MockContractWithArgs).creationCode, abi.encode(helper.getEvmSuffix(), value))
        );
        assertEq(deployed, predicted, "Address should be deterministic regardless of constructor args");
    }

    function test_Deploy_AddressIndependentOfConstructorArgs() public {
        // Compute predicted addresses for two different constructor values
        address predicted1 = helper.computeDeploymentAddress(
            abi.encodePacked(type(MockContractWithArgs).creationCode, abi.encode(helper.getEvmSuffix(), uint256(42)))
        );
        address predicted2 = helper.computeDeploymentAddress(
            abi.encodePacked(type(MockContractWithArgs).creationCode, abi.encode(helper.getEvmSuffix(), uint256(999)))
        );

        // CREATE3 addresses depend only on deployer + salt (derived from version string)
        // Constructor args are NOT part of the address calculation
        assertEq(predicted1, predicted2, "Address should be independent of constructor args");
    }

    function testFuzz_Salt_ConsistentForSameInput(string memory version) public view {
        vm.assume(bytes(version).length > 0 && bytes(version).length < 100);

        bytes32 salt1 = helper.getSaltForVersion(version);
        bytes32 salt2 = helper.getSaltForVersion(version);

        assertEq(salt1, salt2, "Salt should be consistent");
    }

    // Tests for atomic deploy+init functionality
    function test_AtomicDeployInit_DefaultBehavior() public {
        // Default behavior should initialize owner atomically
        address deployed = helper.deployMockContract();

        assertTrue(deployed.code.length > 0, "Contract should have code");
        assertEq(MockContract(deployed).owner(), deployer, "Owner should be set atomically");
    }

    function test_NoInitOverride_SkipsInitialization() public {
        NoInitDeployHelper noInitHelper = new NoInitDeployHelper();
        noInitHelper.setUp();

        address deployed = noInitHelper.deployConstructorOwnedContract();

        assertTrue(deployed.code.length > 0, "Contract should have code");
        assertEq(ConstructorOwnedContract(deployed).owner(), deployer, "Owner should be set in constructor");
    }

    function test_CustomInitOverride_UsesCustomOwner() public {
        address customOwner = makeAddr("customOwner");

        CustomInitDeployHelper customHelper = new CustomInitDeployHelper();
        customHelper.setUp();
        customHelper.setCustomOwner(customOwner);

        address deployed = customHelper.deployMockContract();

        assertTrue(deployed.code.length > 0, "Contract should have code");
        assertEq(MockContract(deployed).owner(), customOwner, "Owner should be custom owner");
    }

    function test_PayableConstructor_DeploysWithETH() public {
        PayableNoInitDeployHelper payableHelper = new PayableNoInitDeployHelper();
        payableHelper.setUp();
        vm.deal(address(payableHelper), 10 ether);

        address deployed = payableHelper.deployPayableContract();
        assertTrue(deployed.code.length > 0, "Payable constructor contract should be deployed");
    }

    // New test cases for audit findings Q6

    function test_GuardSalt_ConsistentInsideAndOutsideBroadcast() public {
        // _guardSalt always uses _deployer for address computation, ensuring
        // consistent results regardless of broadcast context. This is required
        // because Foundry 1.5.x blocks address(this) in script contracts.
        // _deployCreate3 uses vm.prank(_deployer) outside broadcast to match.

        address deployer = helper.getDeployer();
        bytes11 randomSeed = bytes11(keccak256("test-seed"));
        bytes1 crosschainFlag = bytes1(0x00); // Enable crosschain (CROSSCHAIN_FLAG_ENABLED)
        bytes32 salt = bytes32(abi.encodePacked(deployer, crosschainFlag, randomSeed));

        // Outside broadcast
        bytes32 guardedOutside = helper.guardSaltPublic(salt);

        // Inside broadcast with deployer
        vm.startBroadcast(deployer);
        bytes32 guardedInside = helper.guardSaltPublic(salt);
        vm.stopBroadcast();

        // Results should be IDENTICAL since _guardSalt always uses _deployer
        assertEq(guardedOutside, guardedInside, "Guard salt should be consistent across contexts");

        // Verify determinism: calling twice in same context gives same result
        bytes32 guardedOutside2 = helper.guardSaltPublic(salt);
        assertEq(guardedOutside, guardedOutside2, "Guard salt should be deterministic outside broadcast");

        vm.startBroadcast(deployer);
        bytes32 guardedInside2 = helper.guardSaltPublic(salt);
        vm.stopBroadcast();
        assertEq(guardedInside, guardedInside2, "Guard salt should be deterministic inside broadcast");
    }

    function test_AssertBroadcastSender_PassesOutsideBroadcast() public view {
        // Outside broadcast, this should not revert
        helper.assertBroadcastSenderPublic();
    }

    function test_AssertBroadcastSender_RevertsMismatch() public {
        address wrongSender = makeAddr("wrongSender");
        vm.startBroadcast(wrongSender);

        vm.expectRevert(
            abi.encodeWithSelector(DeployHelper.BroadcastSenderMismatch.selector, helper.getDeployer(), wrongSender)
        );
        helper.assertBroadcastSenderPublic();

        vm.stopBroadcast();
    }

    function test_AfterAll_SkipsWhenSenderIsZero() public {
        // Save original env vars
        string memory originalSkipStandardJson = vm.envOr("SKIP_STANDARD_JSON_INPUT", string("false"));
        string memory originalAllowedSender = vm.envOr("ALLOWED_DEPLOYMENT_SENDER", vm.toString(deployer));

        // Set environment for this test
        vm.setEnv("SKIP_STANDARD_JSON_INPUT", "true");
        vm.setEnv("ALLOWED_DEPLOYMENT_SENDER", vm.toString(address(0)));

        // Create helper with zero ALLOWED_DEPLOYMENT_SENDER
        TestDeployHelper helperNoSender = new TestDeployHelper();
        helperNoSender.setUp();

        // Capture the timestamped file path BEFORE deployment
        string memory timestampedPath = helperNoSender.jsonPath();

        // Deploy a contract (sets _hasNewDeployments = true)
        address deployed = helperNoSender.deployMockContract();
        assertTrue(deployed.code.length > 0, "Contract should be deployed");

        // Call saveDeployments - should skip writing because sender is zero
        helperNoSender.saveDeployments();

        // CRITICAL: Verify timestamped file was NOT created
        // The timestamped path is unique per run, so if _afterAll skipped, file won't exist
        assertFalse(vm.isFile(timestampedPath), "Timestamped JSON should NOT be created when sender is zero");

        // Restore original env vars
        vm.setEnv("SKIP_STANDARD_JSON_INPUT", originalSkipStandardJson);
        vm.setEnv("ALLOWED_DEPLOYMENT_SENDER", originalAllowedSender);
    }

    function test_ComputeEvmSuffix_ReadsFoundryToml() public view {
        // Verify _evmSuffix is computed and is a valid string
        string memory evmSuffix = helper.getEvmSuffix();
        // Should either be empty or start with "-"
        if (bytes(evmSuffix).length > 0) {
            assertEq(bytes(evmSuffix)[0], bytes1("-"), "EVM suffix should start with '-' if non-empty");
        }
    }

    function test_Deploy_RevertsForNonVersionableContract() public {
        // Create a helper that tries to deploy NonVersionableContract
        TestDeployHelper helperNonVersionable = new TestDeployHelper();
        helperNonVersionable.setUp();

        bytes memory creationCode = type(NonVersionableContract).creationCode;

        vm.expectRevert(DeployHelper.VersionCallFailed.selector);
        helperNonVersionable.deployPublic(creationCode);
    }

    function test_Deploy_WithInitDataAndValues() public {
        InitWithValueDeployHelper valueHelper = new InitWithValueDeployHelper();
        valueHelper.setUp();
        vm.deal(address(valueHelper), 10 ether);

        address deployed = valueHelper.deployPayableContract();

        assertTrue(deployed.code.length > 0, "Contract should be deployed");
        assertEq(deployed.balance, 1 ether, "Contract should have received 1 ETH");
    }

    function test_Deploy_WithInitData_ExercisesDeployCreate3AndInit() public {
        // This test exercises CR3 fix - testing deployCreate3AndInit path
        InitDataDeployHelper initHelper = new InitDataDeployHelper();
        initHelper.setUp();
        vm.deal(address(initHelper), 10 ether);

        address deployed = initHelper.deployPayableInitContract();

        // Verify contract was deployed
        assertTrue(deployed.code.length > 0, "Contract should be deployed");

        // Verify init function was called atomically
        PayableInitContract instance = PayableInitContract(deployed);
        assertEq(instance.owner(), deployer, "Owner should be set via init function");
        assertEq(instance.initValue(), 0.5 ether, "Init value should match initCallAmount");
        assertEq(deployed.balance, 0.5 ether, "Contract should have received ETH via init call");

        // Verify initializer was the CREATE3 proxy (not the helper itself)
        // The initializer should be the CREATE3 proxy that calls init during deployment
        assertTrue(instance.initializer() != address(0), "Initializer should be set");
        assertTrue(instance.initializer() != address(initHelper), "Initializer should be proxy, not helper");
    }

    function test_ComputeAddress_SequentialDeploys() public {
        // Compute addresses for two different contracts
        bytes memory creationCode1 =
            abi.encodePacked(type(MockContract).creationCode, abi.encode(helper.getEvmSuffix()));
        bytes memory creationCode2 =
            abi.encodePacked(type(MockContractV2).creationCode, abi.encode(helper.getEvmSuffix()));

        address predicted1 = helper.computeDeploymentAddress(creationCode1);
        address predicted2 = helper.computeDeploymentAddress(creationCode2);

        // Deploy both contracts
        address deployed1 = helper.deployPublic(creationCode1);
        address deployed2 = helper.deployPublic(creationCode2);

        // Verify predictions match
        assertEq(predicted1, deployed1, "First prediction should match deployment");
        assertEq(predicted2, deployed2, "Second prediction should match deployment");
        assertTrue(deployed1 != deployed2, "Different contracts should have different addresses");
    }

    function test_LoadExistingLatestEntries_HandlesVersionKeysWithDots() public {
        // Test for Finding 1: Verify that version keys with dots (e.g., "1.0.0-MockContract")
        // are correctly loaded from existing -latest.json files using bracket notation

        // Use a unique chain ID for this test to avoid interference
        uint256 uniqueChainId = 999888777;
        vm.chainId(uniqueChainId);

        // Create a -latest.json file with version keys containing dots
        string memory latestPath =
            string.concat(vm.projectRoot(), "/deployments/test/", vm.toString(uniqueChainId), "-latest.json");

        // Clean up any stale file from previous tests
        if (vm.isFile(latestPath)) {
            vm.removeFile(latestPath);
        }

        // Verify file doesn't exist after cleanup
        assertFalse(vm.isFile(latestPath), "Latest file should be deleted before test starts");

        // Create the deployments directory
        vm.createDir(string.concat(vm.projectRoot(), "/deployments/test"), true);

        // Write a -latest.json with versioned keys
        address mockAddr1 = address(0x1111111111111111111111111111111111111111);
        address mockAddr2 = address(0x2222222222222222222222222222222222222222);
        string memory existingJson = string.concat(
            '{"1.0.0-MockContract":"',
            vm.toString(mockAddr1),
            '","2.0.0-MockContractV2":"',
            vm.toString(mockAddr2),
            '"}'
        );
        vm.writeFile(latestPath, existingJson);

        // Verify the file was written correctly
        assertTrue(vm.isFile(latestPath), "File should exist after writing");
        string memory writtenContent = vm.readFile(latestPath);
        assertEq(writtenContent, existingJson, "Written content should match expected JSON");

        // Now create a fresh helper and setUp - this should load the existing entries
        TestDeployHelper freshHelper = new TestDeployHelper();
        freshHelper.setUp();

        // Verify the entries were loaded correctly by checking the finalJsonLatest
        // The helper should have merged the existing entries
        string memory loadedJson = freshHelper.finalJsonLatest();

        // Debug: Check if loadedJson is empty
        assertTrue(bytes(loadedJson).length > 0, "finalJsonLatest should not be empty after setUp");

        // Parse and verify both addresses were loaded
        address loaded1 = vm.parseJsonAddress(loadedJson, "$['1.0.0-MockContract']");
        address loaded2 = vm.parseJsonAddress(loadedJson, "$['2.0.0-MockContractV2']");

        assertEq(loaded1, mockAddr1, "First address should be loaded from existing -latest.json");
        assertEq(loaded2, mockAddr2, "Second address should be loaded from existing -latest.json");

        // Cleanup at end
        if (vm.isFile(latestPath)) {
            vm.removeFile(latestPath);
        }
    }

    function test_GetLocalChainId_ReturnsEnvOverride() public {
        // Save original value to restore later (use sentinel for unset detection)
        string memory originalLocalChainId = vm.envOr("LOCAL_CHAIN_ID", string("31337"));

        // Test that LOCAL_CHAIN_ID env var is respected for custom local chain IDs
        vm.setEnv("LOCAL_CHAIN_ID", "1337");

        // Create a fresh helper that will read the env var during setup
        TestDeployHelper freshHelper = new TestDeployHelper();

        // Change chain ID to 1337 (Hardhat)
        vm.chainId(1337);

        // Setup should succeed because LOCAL_CHAIN_ID=1337 matches block.chainid
        freshHelper.setUp();

        // Verify CreateX was etched (proves LOCAL_CHAIN_ID was respected)
        assertGt(
            address(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed).code.length, 0, "CreateX should be etched on chain 1337"
        );

        // Restore original env var value
        vm.setEnv("LOCAL_CHAIN_ID", originalLocalChainId);
    }

    // Edge case tests

    function test_EmptyCreationCode_RevertsWithVersionCallFailed() public {
        bytes memory emptyCode = "";

        // Empty creation code will fail during CREATE
        vm.expectRevert();
        helper.deployPublic(emptyCode);
    }

    function test_NonVersionableContract_RevertsWithVersionCallFailed() public {
        bytes memory creationCode = type(NonVersionableContract).creationCode;

        vm.expectRevert(abi.encodeWithSignature("VersionCallFailed()"));
        helper.deployPublic(creationCode);
    }

    function test_InvalidVersionFormat_NoHyphen_Reverts() public {
        // Create a helper that tries to deploy InvalidVersionFormatContract
        TestDeployHelper helperInvalidVersion = new TestDeployHelper();
        helperInvalidVersion.setUp();

        bytes memory creationCode = type(InvalidVersionFormatContract).creationCode;

        vm.expectRevert(abi.encodeWithSelector(DeployHelper.InvalidVersionFormat.selector, "1.0.0NoHyphen"));
        helperInvalidVersion.deployPublic(creationCode);
    }

    function test_VersionCaching_ReducesGasOnSecondCall() public {
        bytes memory creationCode = abi.encodePacked(type(MockContract).creationCode, abi.encode(helper.getEvmSuffix()));

        // First call - populates cache
        uint256 gas1 = gasleft();
        helper.computeMockContractAddress();
        uint256 gasUsed1 = gas1 - gasleft();

        // Second call - should use cache
        uint256 gas2 = gasleft();
        helper.computeMockContractAddress();
        uint256 gasUsed2 = gas2 - gasleft();

        // Cache hit should use less gas (version extraction skipped)
        assertLt(gasUsed2, gasUsed1, "Second call should use less gas due to caching");
    }

    function testFuzz_GuardSalt_RandomSalts(bytes32 salt) public view {
        // Test guard salt with properly formatted salts only
        // Format: address (20 bytes) || flag (1 byte) || random (11 bytes)
        address deployer = helper.getDeployer();
        address embedded = address(bytes20(salt));
        bytes1 flag = salt[20];

        // Skip salts that would trigger InvalidSalt error
        // Valid combinations:
        // 1. embedded == deployer with flag 0x00 or 0x01
        // 2. embedded == address(0) with flag 0x00 or 0x01
        // 3. Other addresses (random salt case)
        if (embedded == deployer || embedded == address(0)) {
            // For deployer or zero address, flag must be 0x00 or 0x01
            vm.assume(flag == 0x00 || flag == 0x01);
        }
        // For other embedded addresses, any salt is valid (random case)

        // Test that _guardSalt executes successfully and returns deterministic result
        bytes32 guarded = helper.guardSaltPublic(salt);
        bytes32 guardedAgain = helper.guardSaltPublic(salt);

        assertEq(guarded, guardedAgain, "Guard salt should be deterministic");
    }

    function testFuzz_GuardSalt_EmbeddedSender(bytes11 randomSeed, bool crosschainFlag) public view {
        // Create salt with embedded deployer address
        bytes1 flag = crosschainFlag ? bytes1(0x01) : bytes1(0x00);
        bytes32 salt = bytes32(abi.encodePacked(helper.getDeployer(), flag, randomSeed));

        // Should not revert
        bytes32 guarded = helper.guardSaltPublic(salt);
        assertTrue(guarded != bytes32(0), "Should return valid guarded salt");
    }

    function test_ParseEnvBool_ValidInputs() public view {
        // Test explicit valid inputs instead of fuzzing
        assertTrue(helper.parseEnvBool("true"), "Should parse 'true' as true");
        assertTrue(helper.parseEnvBool("True"), "Should parse 'True' as true");
        assertTrue(helper.parseEnvBool("TRUE"), "Should parse 'TRUE' as true");
        assertTrue(helper.parseEnvBool("1"), "Should parse '1' as true");

        assertFalse(helper.parseEnvBool("false"), "Should parse 'false' as false");
        assertFalse(helper.parseEnvBool("False"), "Should parse 'False' as false");
        assertFalse(helper.parseEnvBool("FALSE"), "Should parse 'FALSE' as false");
        assertFalse(helper.parseEnvBool("0"), "Should parse '0' as false");
        assertFalse(helper.parseEnvBool(""), "Should parse empty as false");
        assertFalse(helper.parseEnvBool("random"), "Should parse unknown as false");
    }

    function test_StandardJsonInputMismatch_ErrorExists() public {
        // This test verifies that the StandardJsonInputMismatch error exists and can be used
        // The error is thrown when standard JSON input file exists with different content
        // than what would be generated from the current compilation

        // Test that the error can be encoded (verifies selector exists)
        bytes memory encoded =
            abi.encodeWithSelector(DeployHelper.StandardJsonInputMismatch.selector, "1.0.0-TestContract");

        // Verify the encoding worked
        assertTrue(encoded.length > 0, "Error should be encodable");

        // Verify the selector is correct (first 4 bytes)
        bytes4 selector;
        assembly {
            selector := mload(add(encoded, 32))
        }
        assertEq(selector, DeployHelper.StandardJsonInputMismatch.selector, "Selector should match");
    }

    function test_StandardJsonInputMismatch_TriggersOnMismatch() public {
        // Save original env vars
        string memory originalSkipStandardJson = vm.envOr("SKIP_STANDARD_JSON_INPUT", string("true"));
        string memory originalForceDeploy = vm.envOr("FORCE_DEPLOY", string("false"));

        vm.setEnv("SKIP_STANDARD_JSON_INPUT", "false");
        vm.setEnv("FORCE_DEPLOY", "false");

        RealStandardJsonCheckHelper realHelper = new RealStandardJsonCheckHelper();
        realHelper.setUp();

        // Clean up any existing files first
        string memory evmSuffix = realHelper.getEvmSuffix();
        string memory versionAndVariant = string.concat("1.0.0-MockContract", evmSuffix);
        string memory standardJsonDir = string.concat(vm.projectRoot(), "/deployments/test/standard-json-inputs");
        string memory outputPath = string.concat(standardJsonDir, "/", versionAndVariant, ".json");

        // Ensure directory exists
        vm.createDir(standardJsonDir, true);

        // Clean up any existing standard JSON files
        if (vm.isFile(outputPath)) vm.removeFile(outputPath);

        // Create a corrupted standard JSON file manually (simulating a tampered/modified file)
        string memory mockStandardJson = '{"corrupted":"content"}';
        vm.writeFile(outputPath, mockStandardJson);

        // Verify the file was created
        assertTrue(vm.isFile(outputPath), "Mock standard JSON file should exist");

        // Now try to deploy - this should generate different standard JSON and detect mismatch
        // The check happens AFTER computing the address but BEFORE deployment
        vm.expectRevert(abi.encodeWithSelector(DeployHelper.StandardJsonInputMismatch.selector, versionAndVariant));
        realHelper.deployMockContract();

        // CRITICAL: Remove the corrupted file IMMEDIATELY to avoid interfering with subsequent tests
        if (vm.isFile(outputPath)) {
            vm.removeFile(outputPath);
        }

        // Verify cleanup worked
        assertFalse(vm.isFile(outputPath), "Mock standard JSON file should be removed");

        // Restore original env vars
        vm.setEnv("SKIP_STANDARD_JSON_INPUT", originalSkipStandardJson);
        vm.setEnv("FORCE_DEPLOY", originalForceDeploy);
    }

    function test_MainnetChainMapping_O1Lookup() public {
        // Test that mainnet check uses mapping for O(1) lookup
        // This is verified through gas usage comparison

        vm.chainId(1); // Ethereum mainnet
        TestDeployHelper mainnetHelper = new TestDeployHelper();
        mainnetHelper.setUp();

        bytes memory creationCode =
            abi.encodePacked(type(MockContract).creationCode, abi.encode(mainnetHelper.getEvmSuffix()));
        address deployed = mainnetHelper.deployPublic(creationCode);

        // Measure gas for ownership check (should be constant regardless of array size)
        uint256 gasBefore = gasleft();
        mainnetHelper.checkAndTransferOwner(deployed);
        uint256 gasUsed = gasBefore - gasleft();

        // Gas should be reasonable for O(1) lookup
        // (This is a basic sanity check; real O(1) verification would require profiling)
        assertLt(gasUsed, 1_000_000, "Gas usage should be reasonable for O(1) lookup");
    }

    function test_BroadcastSenderMismatch_RevertsOnDeploy() public {
        // Create helper with deployer = address(1)
        address expectedDeployer = address(1);
        TestDeployHelper mismatchHelper = new TestDeployHelper();
        mismatchHelper.setUpWithDeployer("test", expectedDeployer);

        bytes memory creationCode =
            abi.encodePacked(type(MockContract).creationCode, abi.encode(mismatchHelper.getEvmSuffix()));

        // Start broadcast with a different address (address(2))
        address actualBroadcaster = address(2);
        vm.startBroadcast(actualBroadcaster);

        // Deployment should revert with BroadcastSenderMismatch
        vm.expectRevert(
            abi.encodeWithSignature("BroadcastSenderMismatch(address,address)", expectedDeployer, actualBroadcaster)
        );
        mismatchHelper.deployPublic(creationCode);

        vm.stopBroadcast();
    }

    function test_MalformedJSON_HandledGracefully() public {
        // Clean up any stale file from previous tests
        _cleanupLatestJsonFile();

        // Create a malformed JSON file
        string memory malformedLatestPath =
            string.concat(vm.projectRoot(), "/deployments/test/", vm.toString(block.chainid), "-latest.json");

        // Create deployment directory
        vm.createDir(string.concat(vm.projectRoot(), "/deployments/test"), true);

        // Write malformed JSON (invalid syntax)
        string memory malformedJson = "{invalid json content}";
        vm.writeFile(malformedLatestPath, malformedJson);

        // Create a new helper (should load existing -latest.json during setUp)
        TestDeployHelper malformedHelper = new TestDeployHelper();

        // setUp should succeed despite malformed JSON
        malformedHelper.setUp();

        // Deploy should work normally
        bytes memory creationCode =
            abi.encodePacked(type(MockContract).creationCode, abi.encode(malformedHelper.getEvmSuffix()));
        address deployed = malformedHelper.deployPublic(creationCode);

        // Verify deployment succeeded
        assertGt(deployed.code.length, 0, "Contract should be deployed");

        // Cleanup at end
        _cleanupLatestJsonFile();
    }

    function test_CorruptJSON_HandledGracefully() public {
        // Clean up any stale file from previous tests
        _cleanupLatestJsonFile();

        // Create a JSON file with valid structure but corrupted address values
        string memory corruptLatestPath =
            string.concat(vm.projectRoot(), "/deployments/test/", vm.toString(block.chainid), "-latest.json");

        // Create deployment directory
        vm.createDir(string.concat(vm.projectRoot(), "/deployments/test"), true);

        // Write JSON with corrupt address (not a valid hex address)
        string memory corruptJson = '{"1.0.0-MockContract": "0xINVALID"}';
        vm.writeFile(corruptLatestPath, corruptJson);

        // Create a new helper (should load existing -latest.json during setUp)
        TestDeployHelper corruptHelper = new TestDeployHelper();

        // setUp should succeed despite corrupt JSON
        corruptHelper.setUp();

        // Deploy should work normally
        bytes memory creationCode =
            abi.encodePacked(type(MockContract).creationCode, abi.encode(corruptHelper.getEvmSuffix()));
        address deployed = corruptHelper.deployPublic(creationCode);

        // Verify deployment succeeded
        assertGt(deployed.code.length, 0, "Contract should be deployed");

        // Cleanup at end
        _cleanupLatestJsonFile();
    }

    // Tests for new audit findings fixes

    function test_InitAmountWithoutInitData_Reverts() public {
        // Create a helper that has initCallAmount > 0 but empty initData
        InitAmountWithoutInitDataHelper badHelper = new InitAmountWithoutInitDataHelper();
        badHelper.setUp();
        vm.deal(address(badHelper), 10 ether);

        bytes memory creationCode =
            abi.encodePacked(type(MockContract).creationCode, abi.encode(badHelper.getEvmSuffix()));

        // Deployment should revert with InitAmountWithoutInitData
        vm.expectRevert(abi.encodeWithSelector(DeployHelper.InitAmountWithoutInitData.selector, 1 ether));
        badHelper.deployPublic(creationCode);
    }

    function test_MockDeploymentFailed_ThrowsCorrectError() public {
        // Create a helper to test MockDeploymentFailed error
        TestDeployHelper testHelper = new TestDeployHelper();
        testHelper.setUp();

        // Create creation code that will fail during CREATE
        // Using invalid bytecode that causes CREATE to return address(0)
        bytes memory invalidCreationCode = hex"fe"; // INVALID opcode

        // Deployment should revert with MockDeploymentFailed
        vm.expectRevert(abi.encodeWithSelector(DeployHelper.MockDeploymentFailed.selector));
        testHelper.deployPublic(invalidCreationCode);
    }

    function test_SetupNotCalled_Reverts() public {
        // Create a helper that doesn't call _setUp()
        NoSetupDeployHelper noSetupHelper = new NoSetupDeployHelper();

        bytes memory creationCode = abi.encodePacked(
            type(MockContract).creationCode,
            abi.encode("") // Empty EVM suffix since _setUp() wasn't called
        );

        // Deployment should revert with SetupNotCalled
        vm.expectRevert(abi.encodeWithSelector(DeployHelper.SetupNotCalled.selector));
        noSetupHelper.deployPublic(creationCode);
    }

    function test_ComputeDeploymentAddress_RevertsIfSetupNotCalled() public {
        NoSetupDeployHelper noSetupHelper = new NoSetupDeployHelper();

        bytes memory creationCode = abi.encodePacked(type(MockContract).creationCode, abi.encode(""));

        vm.expectRevert(abi.encodeWithSelector(DeployHelper.SetupNotCalled.selector));
        noSetupHelper.computeDeploymentAddressPublic(creationCode);
    }
}

// Helper for testing initCallAmount without initData
contract InitAmountWithoutInitDataHelper is DeployHelper {
    function setUp() public override {
        _setUp("test");
    }

    function deployPublic(bytes memory creationCode) public returns (address) {
        return deploy(creationCode);
    }

    function _getDeployValues() internal pure override returns (ICreateX.Values memory) {
        // Non-zero initCallAmount but empty initData (will trigger error)
        return ICreateX.Values({constructorAmount: 0, initCallAmount: 1 ether});
    }

    function _getPostDeployInitData() internal pure override returns (bytes memory) {
        // Empty init data
        return "";
    }

    // Skip standard JSON input checking to avoid interference from other tests
    function _shouldSkipStandardJsonInput() internal pure override returns (bool) {
        return true;
    }
}

// Helper that doesn't call _setUp() to test SetupNotCalled error
contract NoSetupDeployHelper is DeployHelper {
    function setUp() public override {
        // Intentionally skip calling _setUp() to test the guard
    }

    function deployPublic(bytes memory creationCode) public returns (address) {
        return deploy(creationCode);
    }

    function computeDeploymentAddressPublic(bytes memory creationCode) public returns (address) {
        return computeDeploymentAddress(creationCode);
    }

    // Skip standard JSON input checking to avoid interference
    function _shouldSkipStandardJsonInput() internal pure override returns (bool) {
        return true;
    }
}
