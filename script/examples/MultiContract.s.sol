// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DeployHelper} from "../../src/DeployHelper.sol";
import {Versionable} from "../../src/Versionable.sol";
import {Ownable} from "solady/auth/Ownable.sol";

/**
 * @title ExampleToken
 * @notice Example token contract
 */
contract ExampleToken is Versionable, Ownable {
    string public name = "Example Token";
    string public symbol = "EXT";
    uint256 public totalSupply;

    constructor(string memory evmSuffix_) Versionable(evmSuffix_) {}

    function initializeOwner(address _owner) external {
        require(owner() == address(0), "Already initialized");
        _initializeOwner(_owner);
    }

    function mint(uint256 amount) external onlyOwner {
        totalSupply += amount;
    }

    function _baseVersion() internal pure override returns (string memory) {
        return "1.0.0-ExampleToken";
    }
}

/**
 * @title ExampleVault
 * @notice Example vault contract
 */
contract ExampleVault is Versionable, Ownable {
    address public token;

    constructor(string memory evmSuffix_) Versionable(evmSuffix_) {}

    function initializeOwner(address _owner) external {
        require(owner() == address(0), "Already initialized");
        _initializeOwner(_owner);
    }

    function setToken(address _token) external onlyOwner {
        token = _token;
    }

    function _baseVersion() internal pure override returns (string memory) {
        return "1.0.0-ExampleVault";
    }
}

/**
 * @title ExampleRouter
 * @notice Example router contract
 */
contract ExampleRouter is Versionable, Ownable {
    address public token;
    address public vault;
    bool public initialized;

    constructor(string memory evmSuffix_) Versionable(evmSuffix_) {}

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
        return "1.0.0-ExampleRouter";
    }
}

/**
 * @title MultiContract
 * @notice Example deployment script showing multi-contract deployment with atomic init
 * @dev This demonstrates:
 *      - Deploying multiple contracts with atomic initialization
 *      - Initializing contracts with cross-references (requires ownership)
 *      - Managing ownership for multiple contracts
 *
 *      Atomic init is needed here because setToken() and initialize() are onlyOwner.
 *      Without atomic init, an attacker could front-run and claim ownership between
 *      deployment and initialization.
 */
contract MultiContract is DeployHelper {
    function setUp() public override {
        // Use DEPLOYER env var if set, otherwise use msg.sender (script contract)
        // When broadcasting, DEPLOYER should be set to the broadcaster EOA
        address broadcaster = vm.envOr("DEPLOYER", msg.sender);
        _setUp("multi", broadcaster);
    }

    /// @notice Atomic initialization: deploy and call initializeOwner in one transaction
    /// @dev Required because post-deploy cross-reference calls (setToken, initialize) need ownership
    function _getPostDeployInitData() internal override returns (bytes memory) {
        return abi.encodeWithSignature("initializeOwner(address)", _deployer);
    }

    function run() public {
        vm.startBroadcast(_deployer);
        _assertBroadcastSenderMatchesDeployer();

        address token = deploy(abi.encodePacked(type(ExampleToken).creationCode, abi.encode(_getEvmSuffix())));
        address vault = deploy(abi.encodePacked(type(ExampleVault).creationCode, abi.encode(_getEvmSuffix())));
        address router = deploy(abi.encodePacked(type(ExampleRouter).creationCode, abi.encode(_getEvmSuffix())));

        if (ExampleVault(vault).token() == address(0)) {
            ExampleVault(vault).setToken(token);
        }
        if (!ExampleRouter(router).initialized()) {
            ExampleRouter(router).initialize(token, vault);
        }

        _checkChainAndSetOwner(token);
        _checkChainAndSetOwner(vault);
        _checkChainAndSetOwner(router);

        _afterAll();

        vm.stopBroadcast();
    }
}
