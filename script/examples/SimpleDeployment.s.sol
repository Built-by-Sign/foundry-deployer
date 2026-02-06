// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DeployHelper} from "../../src/DeployHelper.sol";
import {Versionable} from "../../src/Versionable.sol";
import {Ownable} from "solady/auth/Ownable.sol";

/**
 * @title MyContract
 * @notice Example contract that implements IVersionable
 * @dev Constructor-based ownership: owner is set in the constructor,
 *      so no post-deploy initialization is needed. This is the simplest pattern.
 */
contract MyContract is Versionable, Ownable {
    uint256 public value;

    constructor(string memory evmSuffix_, address owner_) Versionable(evmSuffix_) {
        _initializeOwner(owner_);
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
 * @notice Basic single-contract deployment with constructor-based ownership
 */
contract SimpleDeployment is DeployHelper {
    function setUp() public override {
        // Use DEPLOYER env var if set, otherwise use msg.sender (script contract)
        // When broadcasting, DEPLOYER should be set to the broadcaster EOA
        address broadcaster = vm.envOr("DEPLOYER", msg.sender);
        _setUp("examples", broadcaster);
    }

    function run() public {
        vm.startBroadcast(_deployer);
        _assertBroadcastSenderMatchesDeployer();

        bytes memory creationCode =
            abi.encodePacked(type(MyContract).creationCode, abi.encode(_getEvmSuffix(), _deployer));
        address deployed = deploy(creationCode);

        _checkChainAndSetOwner(deployed);
        _afterAll();

        vm.stopBroadcast();
    }
}
