// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DeployHelper} from "../../src/DeployHelper.sol";
import {Versionable} from "../../src/Versionable.sol";
import {IVersionable} from "../../src/interfaces/IVersionable.sol";
import {Ownable} from "solady/auth/Ownable.sol";

// Example contracts for E2E testing
contract E2EToken is Versionable, Ownable {
    string public name = "Test Token";
    string public symbol = "TEST";
    uint256 public totalSupply;

    constructor(string memory evmSuffix_) Versionable(evmSuffix_) {
        // Don't initialize owner here - will be initialized after deployment
    }

    function initializeOwner(address _owner) external {
        require(owner() == address(0), "Already initialized");
        _initializeOwner(_owner);
    }

    function mint(uint256 amount) external onlyOwner {
        totalSupply += amount;
    }

    function _baseVersion() internal pure override returns (string memory) {
        return "1.0.0-E2EToken";
    }
}

contract E2EVault is Versionable, Ownable {
    address public token;

    constructor(string memory evmSuffix_) Versionable(evmSuffix_) {
        // Don't initialize owner here - will be initialized after deployment
    }

    function initializeOwner(address _owner) external {
        require(owner() == address(0), "Already initialized");
        _initializeOwner(_owner);
    }

    function setToken(address _token) external onlyOwner {
        token = _token;
    }

    function _baseVersion() internal pure override returns (string memory) {
        return "1.0.0-E2EVault";
    }
}

contract E2ERouter is Versionable, Ownable {
    address public token;
    address public vault;
    bool public initialized;

    constructor(string memory evmSuffix_) Versionable(evmSuffix_) {
        // Don't initialize owner here - will be initialized after deployment
    }

    function initializeOwner(address _owner) external {
        require(owner() == address(0), "Already initialized");
        _initializeOwner(_owner);
    }

    function initialize(address _token, address _vault) external onlyOwner {
        require(!initialized, "Already initialized");
        token = _token;
        vault = _vault;
        initialized = true;
    }

    function _baseVersion() internal pure override returns (string memory) {
        return "1.0.0-E2ERouter";
    }
}

// E2E deployment script
contract E2EDeployScript is DeployHelper {
    address public tokenAddr;
    address public vaultAddr;
    address public routerAddr;

    function setUp() public override {
        _setUp("e2e-test");
    }

    function run() public {
        // Deploy contracts (owner will be set to _deployer)
        tokenAddr = deploy(abi.encodePacked(type(E2EToken).creationCode, abi.encode(_getEvmSuffix())));
        vaultAddr = deploy(abi.encodePacked(type(E2EVault).creationCode, abi.encode(_getEvmSuffix())));
        routerAddr = deploy(abi.encodePacked(type(E2ERouter).creationCode, abi.encode(_getEvmSuffix())));

        // Initialize with cross-references (only if not already initialized)
        // Use prank to call as deployer since they are owner-only functions
        if (E2EVault(vaultAddr).token() == address(0)) {
            vm.prank(_deployer);
            E2EVault(vaultAddr).setToken(tokenAddr);
        }
        if (!E2ERouter(routerAddr).initialized()) {
            vm.prank(_deployer);
            E2ERouter(routerAddr).initialize(tokenAddr, vaultAddr);
        }

        // Transfer ownership (prank handled internally by _checkChainAndSetOwner)
        _checkChainAndSetOwner(tokenAddr);
        _checkChainAndSetOwner(vaultAddr);
        _checkChainAndSetOwner(routerAddr);

        // Save artifacts
        _afterAll();
    }
}

// E2E deployment script with separated phases for explicit ownership testing
contract E2EDeployScriptSplitPhases is DeployHelper {
    address public tokenAddr;
    address public vaultAddr;
    address public routerAddr;

    function setUp() public override {
        _setUp("e2e-test");
    }

    // Phase 1: Deploy contracts only (no ownership transfer)
    function deployOnly() public {
        tokenAddr = deploy(abi.encodePacked(type(E2EToken).creationCode, abi.encode(_getEvmSuffix())));
        vaultAddr = deploy(abi.encodePacked(type(E2EVault).creationCode, abi.encode(_getEvmSuffix())));
        routerAddr = deploy(abi.encodePacked(type(E2ERouter).creationCode, abi.encode(_getEvmSuffix())));

        // Initialize cross-references
        if (E2EVault(vaultAddr).token() == address(0)) {
            vm.prank(_deployer);
            E2EVault(vaultAddr).setToken(tokenAddr);
        }
        if (!E2ERouter(routerAddr).initialized()) {
            vm.prank(_deployer);
            E2ERouter(routerAddr).initialize(tokenAddr, vaultAddr);
        }
    }

    // Phase 2: Transfer ownership
    function transferOwnership() public {
        _checkChainAndSetOwner(tokenAddr);
        _checkChainAndSetOwner(vaultAddr);
        _checkChainAndSetOwner(routerAddr);
    }
}

contract E2ETest is Test {
    E2EDeployScript public script;
    address public deployer;
    address public prodOwner;

    function setUp() public {
        deployer = address(this);
        prodOwner = makeAddr("prodOwner");

        // Set environment variables
        vm.setEnv("PROD_OWNER", vm.toString(prodOwner));
        vm.setEnv("MAINNET_CHAIN_IDS", "1,56,137,8453");
        vm.setEnv("FORCE_DEPLOY", "true");
        vm.setEnv("SKIP_STANDARD_JSON_INPUT", "true");
        // Don't set ALLOWED_DEPLOYMENT_SENDER to keep tests hermetic (prevents writing to deployments/)

        script = new E2EDeployScript();
        script.setUp();
    }

    function test_E2E_FullDeploymentFlow() public {
        // Run full deployment
        script.run();

        // Verify all contracts deployed
        assertTrue(script.tokenAddr().code.length > 0, "Token should be deployed");
        assertTrue(script.vaultAddr().code.length > 0, "Vault should be deployed");
        assertTrue(script.routerAddr().code.length > 0, "Router should be deployed");

        // Verify initialization
        assertEq(E2EVault(script.vaultAddr()).token(), script.tokenAddr(), "Vault should reference token");
        assertTrue(E2ERouter(script.routerAddr()).initialized(), "Router should be initialized");
        assertEq(E2ERouter(script.routerAddr()).token(), script.tokenAddr(), "Router should reference token");
        assertEq(E2ERouter(script.routerAddr()).vault(), script.vaultAddr(), "Router should reference vault");

        // Verify ownership (on testnet, should remain deployer)
        assertEq(Ownable(script.tokenAddr()).owner(), deployer, "Token owner should be deployer on testnet");
        assertEq(Ownable(script.vaultAddr()).owner(), deployer, "Vault owner should be deployer on testnet");
        assertEq(Ownable(script.routerAddr()).owner(), deployer, "Router owner should be deployer on testnet");
    }

    function test_E2E_OwnershipTransferOnMainnet() public {
        vm.chainId(1);

        // Use split-phase script for explicit ownership testing
        E2EDeployScriptSplitPhases splitScript = new E2EDeployScriptSplitPhases();
        splitScript.setUp();

        // Phase 1: Deploy only (no ownership transfer yet)
        splitScript.deployOnly();

        address expectedDeployer = address(this);

        // CRITICAL: Verify initial ownership state BEFORE transfer
        assertEq(Ownable(splitScript.tokenAddr()).owner(), expectedDeployer, "Token initial owner should be deployer");
        assertEq(Ownable(splitScript.vaultAddr()).owner(), expectedDeployer, "Vault initial owner should be deployer");
        assertEq(Ownable(splitScript.routerAddr()).owner(), expectedDeployer, "Router initial owner should be deployer");

        // Phase 2: Transfer ownership
        splitScript.transferOwnership();

        // Verify ownership was transferred TO prodOwner
        assertEq(Ownable(splitScript.tokenAddr()).owner(), prodOwner, "Token owner should be prod owner");
        assertEq(Ownable(splitScript.vaultAddr()).owner(), prodOwner, "Vault owner should be prod owner");
        assertEq(Ownable(splitScript.routerAddr()).owner(), prodOwner, "Router owner should be prod owner");
    }

    function test_E2E_IdempotentDeployment() public {
        // First deployment
        script.run();

        address token1 = script.tokenAddr();
        address vault1 = script.vaultAddr();
        address router1 = script.routerAddr();

        // Second deployment (should reuse same addresses)
        E2EDeployScript script2 = new E2EDeployScript();
        script2.setUp();

        script2.run();

        assertEq(script2.tokenAddr(), token1, "Token address should be same");
        assertEq(script2.vaultAddr(), vault1, "Vault address should be same");
        assertEq(script2.routerAddr(), router1, "Router address should be same");
    }

    function test_E2E_DifferentDeployersGetDifferentAddresses() public {
        // First deployer
        script.run();

        address token1 = script.tokenAddr();

        // Second deployer - only check address computation, not full deployment
        // (full deployment hits gas limit due to large file I/O operations)
        address deployer2 = makeAddr("deployer2");
        vm.prank(deployer2);
        E2EDeployScript script2 = new E2EDeployScript();
        vm.prank(deployer2);
        script2.setUp();

        // Compute address without deploying - much cheaper
        address token2 = script2.computeDeploymentAddress(
            abi.encodePacked(type(E2EToken).creationCode, abi.encode(script2.getEvmSuffix()))
        );

        assertTrue(token2 != token1, "Different deployers should get different addresses");
    }

    function test_E2E_MultiChainConsistency() public {
        // Deploy on Ethereum
        vm.chainId(1);
        E2EDeployScript ethScript = new E2EDeployScript();
        ethScript.setUp();

        ethScript.run();

        address ethToken = ethScript.tokenAddr();
        address ethVault = ethScript.vaultAddr();

        // Deploy on Base with same deployer
        vm.chainId(8453);
        E2EDeployScript baseScript = new E2EDeployScript();
        baseScript.setUp();

        baseScript.run();

        address baseToken = baseScript.tokenAddr();
        address baseVault = baseScript.vaultAddr();

        // Addresses should be the same (CREATE3)
        assertEq(ethToken, baseToken, "Token address should be consistent across chains");
        assertEq(ethVault, baseVault, "Vault address should be consistent across chains");
    }

    function test_E2E_VersionExtraction() public {
        script.run();

        // Verify versions
        string memory suffix = script.getEvmSuffix();
        assertEq(
            IVersionable(script.tokenAddr()).version(),
            string.concat("1.0.0-E2EToken", suffix),
            "Token version should be correct"
        );
        assertEq(
            IVersionable(script.vaultAddr()).version(),
            string.concat("1.0.0-E2EVault", suffix),
            "Vault version should be correct"
        );
        assertEq(
            IVersionable(script.routerAddr()).version(),
            string.concat("1.0.0-E2ERouter", suffix),
            "Router version should be correct"
        );
    }
}

// ExampleScriptTest removed - example scripts should be tested manually or in separate integration tests
