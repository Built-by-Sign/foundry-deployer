// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DeployHelper} from "../../src/DeployHelper.sol";
import {Versionable} from "../../src/Versionable.sol";
import {Ownable} from "solady/auth/Ownable.sol";

/**
 * @title MyContract
 * @notice Example contract that implements IVersionable
 * @dev This is a simple example contract to demonstrate the deployment system
 */
contract MyContract is Versionable, Ownable {
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

    function _baseVersion() internal pure override returns (string memory) {
        return "1.0.0-MyContract";
    }
}

/**
 * @title SimpleDeployment
 * @notice Example deployment script showing basic usage of foundry-deployer
 * @dev This demonstrates:
 *      - Basic contract deployment
 *      - Ownership transfer on mainnet
 *      - Deployment artifact saving
 */
contract SimpleDeployment is DeployHelper {
    function setUp() public override {
        // Use DEPLOYER env var if set, otherwise use msg.sender (script contract)
        // When broadcasting, DEPLOYER should be set to the broadcaster EOA
        address broadcaster = vm.envOr("DEPLOYER", msg.sender);
        _setUp("examples", broadcaster);
    }

    function run() public {
        // Wrap all deployment calls in broadcast
        // This ensures transactions are recorded when using --broadcast flag
        // SECURITY: Never hardcode private keys. Use:
        //   forge script ... --private-key $PRIVATE_KEY
        // or hardware wallet: --ledger / --trezor
        vm.startBroadcast(_deployer);
        _assertBroadcastSenderMatchesDeployer();

        // Deploy contract using CREATE3
        // EVM suffix is auto-detected from foundry.toml
        bytes memory creationCode = abi.encodePacked(type(MyContract).creationCode, abi.encode(_getEvmSuffix()));
        address deployed = deploy(creationCode);

        // Transfer ownership on mainnet (automatic based on MAINNET_CHAIN_IDS)
        _checkChainAndSetOwner(deployed);

        // Save deployment artifacts to JSON
        _afterAll();

        vm.stopBroadcast();
    }
}
