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

    constructor(string memory evmSuffix_) Versionable(evmSuffix_) {
        // Don't initialize owner here - will be initialized after deployment
    }

    function initializeOwner(address _owner) external {
        require(owner() == address(0), "Already initialized");
        _initializeOwner(_owner);
    }

    function mint(uint256 amount) external onlyOwner {
        totalSupply += amount;
        // simplified: no actual balance tracking
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
        return "1.0.0-ExampleRouter";
    }
}

/**
 * @title MultiContract
 * @notice Example deployment script showing multi-contract deployment
 * @dev This demonstrates:
 *      - Deploying multiple contracts
 *      - Initializing contracts with cross-references
 *      - Managing ownership for multiple contracts
 */
contract MultiContract is DeployHelper {
    function setUp() public override {
        // Use DEPLOYER env var if set, otherwise use msg.sender (script contract)
        // When broadcasting, DEPLOYER should be set to the broadcaster EOA
        address broadcaster = vm.envOr("DEPLOYER", msg.sender);
        _setUp("multi", broadcaster);
    }

    function run() public {
        // Wrap all deployment and initialization calls in broadcast
        // This ensures transactions are recorded when using --broadcast flag
        // SECURITY: Never hardcode private keys. Use:
        //   forge script ... --private-key $PRIVATE_KEY
        // or hardware wallet: --ledger / --trezor
        vm.startBroadcast(_deployer);
        _assertBroadcastSenderMatchesDeployer();

        // Deploy multiple contracts using CREATE3
        // EVM suffix is auto-detected from foundry.toml
        address token = deploy(abi.encodePacked(type(ExampleToken).creationCode, abi.encode(_getEvmSuffix())));
        address vault = deploy(abi.encodePacked(type(ExampleVault).creationCode, abi.encode(_getEvmSuffix())));
        address router = deploy(abi.encodePacked(type(ExampleRouter).creationCode, abi.encode(_getEvmSuffix())));

        // Initialize contracts with cross-references
        if (ExampleVault(vault).token() == address(0)) {
            ExampleVault(vault).setToken(token);
        }
        if (!ExampleRouter(router).initialized()) {
            ExampleRouter(router).initialize(token, vault);
        }

        // Transfer ownership for all contracts on mainnet
        _checkChainAndSetOwner(token);
        _checkChainAndSetOwner(vault);
        _checkChainAndSetOwner(router);

        // Save all deployment artifacts
        _afterAll();

        vm.stopBroadcast();
    }
}
