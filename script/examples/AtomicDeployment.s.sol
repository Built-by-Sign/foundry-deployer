// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DeployHelper} from "../../src/DeployHelper.sol";
import {Versionable} from "../../src/Versionable.sol";
import {Ownable} from "solady/auth/Ownable.sol";

/**
 * @title AtomicContract
 * @notice Example contract using post-deploy initialization (not constructor-based)
 * @dev Owner is set via initializeOwner() after deployment, NOT in the constructor.
 *      This pattern requires atomic deploy+init to prevent front-running.
 */
contract AtomicContract is Versionable, Ownable {
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
        return "1.0.0-AtomicContract";
    }
}

/**
 * @title AtomicDeployment
 * @notice Example deployment script demonstrating atomic deploy+init
 * @dev This demonstrates:
 *      - Atomic deployment and initialization in a single transaction
 *      - Front-running prevention via CreateX's deployCreate3AndInit
 *      - Overriding _getPostDeployInitData() to enable atomic init
 *      - Overriding _getDeployValues() to send ETH during deployment
 *
 *      Without atomic init, there is a window between deployment and the
 *      initializeOwner() call where an attacker could front-run and claim
 *      ownership. Atomic init closes this window by executing both in one tx.
 */
contract AtomicDeployment is DeployHelper {
    function setUp() public override {
        address broadcaster = vm.envOr("DEPLOYER", msg.sender);
        _setUp("examples", broadcaster);
    }

    /// @notice Atomic init: calls initializeOwner in the same tx as deployment
    function _getPostDeployInitData() internal virtual override returns (bytes memory) {
        return abi.encodeWithSignature("initializeOwner(address)", _deployer);
    }

    function run() public {
        vm.startBroadcast(_deployer);
        _assertBroadcastSenderMatchesDeployer();

        bytes memory creationCode = abi.encodePacked(type(AtomicContract).creationCode, abi.encode(_getEvmSuffix()));
        address deployed = deploy(creationCode);

        _checkChainAndSetOwner(deployed);

        _afterAll();
        vm.stopBroadcast();
    }
}
