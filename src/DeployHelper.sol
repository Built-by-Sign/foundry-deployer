// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console} from "forge-std/console.sol";
import {stdToml} from "forge-std/StdToml.sol";
import {Vm, VmSafe} from "forge-std/Vm.sol";
import {CreateXHelper} from "./CreateXHelper.sol";
import {ICreateX} from "./interfaces/ICreateX.sol";
import {IVersionable} from "./interfaces/IVersionable.sol";
import {strings} from "./helpers/strings.sol";
import {Ownable} from "solady/auth/Ownable.sol";

/**
 * @title DeployHelper
 * @notice Base contract for deterministic CREATE3 deployments with version tracking
 * @dev Provides infrastructure for deploying contracts using CREATE3, tracking deployments
 *      in JSON files, and managing ownership transfers for mainnet deployments.
 *      Override virtual methods to customize behavior.
 */
abstract contract DeployHelper is CreateXHelper {
    using strings for string;
    using strings for strings.slice;
    using stdToml for string;

    // Custom errors
    error SetupNotOverridden();
    error SetupNotCalled();
    error AddressMismatch(address computed, address deployed);
    error OwnerInitializationFailed();
    error InvalidSalt(address sender);
    error BroadcastSenderMismatch(address expected, address actual);
    error ZeroProdOwner();
    error EmptyMainnetChainIds();
    error VersionExtractionFailed(uint256 balance, uint256 required);
    error VersionCallFailed();
    error SnapshotRevertFailed();
    error InvalidVersionFormat(string version);
    error OwnerNotDeployer(address currentOwner, address expectedDeployer);
    error StandardJsonInputMismatch(string versionAndVariant);
    error InitAmountWithoutInitData(uint256 initCallAmount);
    error MockDeploymentFailed();

    // Constants for salt protection flags
    bytes1 internal constant CROSSCHAIN_FLAG_DISABLED = 0x01;
    bytes1 internal constant CROSSCHAIN_FLAG_ENABLED = 0x00;
    bytes1 internal constant ZERO_ADDRESS_MARKER = 0x00;

    /// @notice Path to deployment JSON file with timestamp
    string public jsonPath;

    /// @notice Path to latest deployment JSON file (overwritten each time)
    string public jsonPathLatest;

    /// @notice JSON object key for new deployments in current run
    string public jsonObjKeyDiff;

    /// @notice JSON object key for all deployments (including existing)
    string public jsonObjKeyAll;

    /// @notice Serialized JSON string for new deployments
    string public finalJson;

    /// @notice Serialized JSON string for all deployments
    string public finalJsonLatest;

    /// @notice Unix timestamp for deployment tracking
    string public unixTime;

    /// @notice Deployment category for organizing deployment files
    string public deploymentCategory;

    /// @notice Whether any new deployments were made in this run
    bool internal _hasNewDeployments;

    /// @notice Whether _setUp() has been called
    bool internal _isSetUp;

    // Environment variables
    /// @notice Production owner address (set via PROD_OWNER env var)
    address internal _PROD_OWNER;

    /// @notice Array of mainnet chain IDs (set via MAINNET_CHAIN_IDS env var)
    uint256[] internal _MAINNET_CHAIN_IDS;

    /// @notice Mapping for O(1) mainnet chain ID lookup
    mapping(uint256 => bool) internal _isMainnetChain;

    /// @notice Whether to allow differing verification inputs (set via FORCE_DEPLOY env var)
    bool internal _FORCE_DEPLOY;

    /// @notice Address allowed to save deployment files (set via ALLOWED_DEPLOYMENT_SENDER env var)
    address internal _ALLOWED_DEPLOYMENT_SENDER;

    /// @notice Whether to skip standard JSON input generation/checks (set via SKIP_STANDARD_JSON_INPUT env var)
    bool internal _SKIP_STANDARD_JSON_INPUT;

    /// @notice Address of the deployer (captured at setUp time)
    address internal _deployer;

    /// @notice Cached EVM suffix (computed once in _setUp)
    string internal _evmSuffix;

    /// @notice Cache for version extraction to avoid repeated temporary deployments
    /// @dev Maps creation code hash to version string
    mapping(bytes32 => string) internal _versionCache;

    /// @notice Cache for contract names extracted from version strings
    /// @dev Maps creation code hash to contract name
    mapping(bytes32 => string) internal _nameCache;

    /**
     * @notice Setup function that must be called by inheriting contracts
     * @dev Override this in your contract and call _setUp()
     */
    function setUp() public virtual {
        revert SetupNotOverridden();
    }

    /**
     * @notice Initialize deployment helper with category and explicit deployer
     * @param subfolder Deployment category for organizing deployment files
     * @param deployer Explicit deployer address to use for deployments
     * @dev Reads environment variables and sets up JSON tracking paths
     */
    function _setUp(string memory subfolder, address deployer) internal withCreateX {
        deploymentCategory = subfolder;

        // Set explicit deployer address
        _deployer = deployer;

        // Read environment variables from .env
        _PROD_OWNER = vm.envOr("PROD_OWNER", address(0));
        if (_PROD_OWNER == address(0)) revert ZeroProdOwner();
        uint256[] memory emptyChainIds;
        _MAINNET_CHAIN_IDS = vm.envOr("MAINNET_CHAIN_IDS", ",", emptyChainIds);
        if (_MAINNET_CHAIN_IDS.length == 0) revert EmptyMainnetChainIds();
        // Populate mapping for O(1) lookup
        for (uint256 i = 0; i < _MAINNET_CHAIN_IDS.length; i++) {
            _isMainnetChain[_MAINNET_CHAIN_IDS[i]] = true;
        }
        string memory forceDeployRaw = vm.envOr("FORCE_DEPLOY", string("false"));
        _FORCE_DEPLOY = _parseEnvBool(forceDeployRaw);
        _ALLOWED_DEPLOYMENT_SENDER = vm.envOr("ALLOWED_DEPLOYMENT_SENDER", address(0));
        if (_ALLOWED_DEPLOYMENT_SENDER == address(0)) {
            console.log(
                unicode"⚠️[WARN] ALLOWED_DEPLOYMENT_SENDER not set. Deployment artifacts will NOT be saved."
            );
        }
        string memory skipStandardJsonRaw = vm.envOr("SKIP_STANDARD_JSON_INPUT", string("false"));
        _SKIP_STANDARD_JSON_INPUT = _parseEnvBool(skipStandardJsonRaw);

        unixTime = vm.toString(vm.unixTime());
        jsonPath = string.concat(
            vm.projectRoot(),
            "/deployments/",
            subfolder,
            "/",
            vm.toString(block.chainid),
            "-",
            __getUnixHost(),
            "-",
            unixTime,
            ".json"
        );
        jsonPathLatest = string.concat(
            vm.projectRoot(), "/deployments/", subfolder, "/", vm.toString(block.chainid), "-latest.json"
        );
        jsonObjKeyDiff = string.concat(subfolder, "_deploymentObjKeyDiff");
        jsonObjKeyAll = string.concat(subfolder, "_deploymentObjKeyAll");

        // Load existing -latest.json entries for merging
        _loadExistingLatestEntries();

        // Compute and cache EVM suffix from foundry.toml
        _evmSuffix = _computeEvmSuffix();

        // Mark setup as complete
        _isSetUp = true;
    }

    /**
     * @notice Initialize deployment helper with category
     * @param subfolder Deployment category for organizing deployment files
     * @dev Reads environment variables and sets up JSON tracking paths
     *      Uses msg.sender as deployer address
     */
    function _setUp(string memory subfolder) internal {
        _setUp(subfolder, msg.sender);
    }

    /**
     * @notice Load existing -latest.json entries for merging
     * @dev Reads existing -latest.json file and merges entries into finalJsonLatest.
     *      Gracefully handles missing files. Malformed JSON will cause revert.
     *      Uses helper contract for try/catch (Foundry 1.5.x script limitation).
     */
    function _loadExistingLatestEntries() internal virtual {
        if (!vm.isFile(jsonPathLatest)) return;

        string memory existingJson;
        try vm.readFile(jsonPathLatest) returns (string memory content) {
            existingJson = content;
        } catch {
            console.log(unicode"⚠️[WARN] Failed to read existing -latest.json, starting fresh.");
            return;
        }

        if (bytes(existingJson).length == 0) return;

        // Deploy a temporary helper contract to enable try/catch without this.call
        // (Foundry 1.5.x blocks address(this) usage in script contracts)
        _LatestJsonParser parser = new _LatestJsonParser();
        try parser.parse(existingJson) returns (string[] memory keys, address[] memory addrs) {
            for (uint256 i = 0; i < keys.length; i++) {
                finalJsonLatest = vm.serializeAddress(jsonObjKeyAll, keys[i], addrs[i]);
            }
        } catch Error(string memory reason) {
            console.log(unicode"⚠️[WARN] Failed to parse existing -latest.json, starting fresh. Reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.log(unicode"⚠️[WARN] Failed to parse existing -latest.json, starting fresh.");
            console.logBytes(lowLevelData);
        }
    }

    /**
     * @notice Save deployment artifacts to JSON files
     * @dev Only saves if deployer matches ALLOWED_DEPLOYMENT_SENDER
     *      Writes both timestamped and latest JSON files
     */
    function _afterAll() internal virtual {
        // Only deployer specified in .env can save deployments
        if (_deployer != _ALLOWED_DEPLOYMENT_SENDER) {
            console.log(
                unicode"⚠️[WARN] Skipping deployment save. Deployer %s does not match allowed sender %s",
                _deployer,
                _ALLOWED_DEPLOYMENT_SENDER
            );
            return;
        }

        if (_hasNewDeployments) {
            vm.writeJson(finalJson, jsonPath);
            if (bytes(finalJsonLatest).length > 0) {
                vm.writeJson(finalJsonLatest, jsonPathLatest);
            }
        }
    }

    /**
     * @notice Get initialization data for atomic deploy+init
     * @return initData Calldata to execute after deployment (via regular call in CreateX)
     * @dev Virtual to allow customization. Default returns calldata for initializeOwner(address).
     *      Override to return empty bytes to skip initialization, or custom calldata for different logic.
     *
     *      WARNING: Skipping initialization creates frontrunning risk. Only skip if the contract
     *      sets its owner in the constructor or has other protections.
     */
    function _getPostDeployInitData() internal virtual returns (bytes memory) {
        return abi.encodeWithSignature("initializeOwner(address)", _deployer);
    }

    /**
     * @notice Get ETH values to send during deployment
     * @return values ICreateX.Values struct with constructorAmount and initCallAmount
     * @dev Virtual to allow customization. Default returns zero for both fields.
     *      Override to send ETH during constructor or init call if needed.
     */
    function _getDeployValues() internal virtual returns (ICreateX.Values memory) {
        return ICreateX.Values({constructorAmount: 0, initCallAmount: 0});
    }

    /**
     * @notice Get contract path for verification
     * @return path Contract path (e.g., "src/MyContract.sol") or empty string for bare name
     * @dev Virtual to allow customization. Default returns empty string (bare contract name).
     *      Override to return path when using ambiguous contract names.
     */
    function _getContractPath() internal view virtual returns (string memory) {
        return "";
    }

    /**
     * @notice Transfer ownership to production owner on mainnet chains
     * @param instance Address of the contract to transfer ownership
     * @dev Checks if current chain is in MAINNET_CHAIN_IDS array
     *      Skips if owner is already set to PROD_OWNER
     *      Virtual to allow customization
     */
    function _checkChainAndSetOwner(address instance) internal virtual {
        if (!_isMainnetChain[block.chainid]) {
            console.log(unicode"✅[INFO] Testnet detected, skipping owner reassignment.");
            return;
        }

        // Verify broadcast sender matches deployer if broadcasting
        _assertBroadcastSenderMatchesDeployer();

        // Cache owner to avoid repeated external calls
        address currentOwner = Ownable(instance).owner();

        if (currentOwner == _PROD_OWNER) {
            console.log(
                unicode"✅[INFO] Owner already set to %s for %s, skipping reassignment.", _PROD_OWNER, instance
            );
            return;
        }
        // Verify current owner is the deployer before transferring
        if (currentOwner != _deployer) {
            revert OwnerNotDeployer(currentOwner, _deployer);
        }
        // Transfer ownership as the deployer (current owner)
        // In broadcast mode, sender is already verified as deployer, so skip prank
        (VmSafe.CallerMode callerMode,,) = vm.readCallers();
        if (callerMode != VmSafe.CallerMode.Broadcast && callerMode != VmSafe.CallerMode.RecurrentBroadcast) {
            vm.prank(_deployer);
        }
        Ownable(instance).transferOwnership(_PROD_OWNER);
        console.log(unicode"✅[INFO] Mainnet detected, owner reassigned to %s for %s.", _PROD_OWNER, instance);
    }

    /**
     * @notice Generate salt for CREATE3 deployment
     * @param version Version string to include in salt
     * @return Salt for CREATE3 deployment
     * @dev Virtual to allow customization of salt generation
     *      Default: abi.encodePacked(deployer, 0x00, keccak256(version)[0:11])
     */
    function _getSalt(string memory version) internal view virtual returns (bytes32) {
        bytes1 crosschainProtectionFlag = CROSSCHAIN_FLAG_ENABLED; // Enable crosschain deployments
        bytes11 randomSeed = bytes11(keccak256(abi.encode(version)));
        return bytes32(abi.encodePacked(_deployer, crosschainProtectionFlag, randomSeed));
    }

    /**
     * @notice Replicate CreateX's internal _guard logic for salt protection
     * @param salt The raw salt to guard
     * @return guardedSalt The guarded salt that CreateX will use internally
     * @dev Uses _deployer for salt computation in all contexts to avoid
     *      Foundry 1.5.x's address(this) restriction in script contracts.
     *      During broadcast, CreateX sees the broadcaster EOA as msg.sender,
     *      which matches _deployer. Outside broadcast (e.g., in tests),
     *      callers should use vm.prank(_deployer) before calling CreateX,
     *      or ensure _deployer matches the calling contract address.
     */
    function _guardSalt(bytes32 salt) internal view returns (bytes32) {
        return _guardSaltForSender(salt, _deployer);
    }

    function _assertBroadcastSenderMatchesDeployer() internal view {
        (VmSafe.CallerMode callerMode, address msgSender,) = vm.readCallers();
        if (callerMode == VmSafe.CallerMode.Broadcast || callerMode == VmSafe.CallerMode.RecurrentBroadcast) {
            if (msgSender != _deployer) {
                revert BroadcastSenderMismatch(_deployer, msgSender);
            }
        }
    }

    function _guardSaltForSender(bytes32 salt, address sender) internal view returns (bytes32) {
        bytes1 flag = salt[20];
        address embedded = address(bytes20(salt));

        if (embedded == sender) {
            if (flag == CROSSCHAIN_FLAG_DISABLED) {
                return keccak256(abi.encode(sender, block.chainid, salt));
            }
            if (flag == CROSSCHAIN_FLAG_ENABLED) {
                return _efficientHash(bytes32(uint256(uint160(sender))), salt);
            }
            revert InvalidSalt(sender);
        }

        if (embedded == address(0)) {
            if (flag == CROSSCHAIN_FLAG_DISABLED) {
                return _efficientHash(bytes32(block.chainid), salt);
            }
            if (flag == CROSSCHAIN_FLAG_ENABLED) {
                return keccak256(abi.encode(salt));
            }
            revert InvalidSalt(sender);
        }

        // Random case: hash unless salt is pseudo-random (not applicable for user-defined salts).
        return keccak256(abi.encode(salt));
    }

    function _efficientHash(bytes32 a, bytes32 b) private pure returns (bytes32 hash) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            mstore(0x20, b)
            hash := keccak256(0x00, 0x40)
        }
    }

    /**
     * @notice Deploy a contract using CREATE3
     * @param creationCode Contract creation code
     * @return deployed Address of deployed contract
     * @dev Simplified wrapper around __deploy() for common use case
     */
    function deploy(bytes memory creationCode) internal returns (address deployed) {
        (, deployed) = __deploy(creationCode, deploymentCategory);
    }

    /**
     * @notice Compute deployment address without deploying
     * @param creationCode Contract creation code
     * @return predicted Predicted deployment address
     * @dev Useful for pre-computing addresses before deployment.
     *
     *      IMPORTANT: This function is NOT view/pure - it creates a temporary contract to extract
     *      the version string. Side effects are reverted via vm.revertToState().
     *
     *      WARNING: Publicly callable address prediction allows anyone to pre-compute deployment
     *      addresses. This is acceptable because:
     *      1. CREATE3 addresses are deterministic by design (based on deployer + salt)
     *      2. The deployer and version are already public information
     *      3. Address prediction doesn't grant any control over deployment or the deployed contract
     *
     *      Note: Results depend on broadcast context. Call this function from the same context
     *      (broadcast or non-broadcast) as the actual deployment to get accurate predictions.
     *
     *      CreateX's CREATE3 uses address(createX) as the deployer for the internal CREATE2 proxy.
     */
    function computeDeploymentAddress(bytes memory creationCode) public returns (address predicted) {
        if (!_isSetUp) revert SetupNotCalled();
        (, string memory versionAndVariant) = __getNameVersionAndVariant(creationCode);
        bytes32 salt = _getSalt(versionAndVariant);
        bytes32 guardedSalt = _guardSalt(salt);
        // CREATE3 always uses CreateX as the deployer for the internal CREATE2 proxy
        return createX.computeCreate3Address(guardedSalt, address(createX));
    }

    /**
     * @notice Core deployment function using CREATE3
     * @param creationCode Contract creation code
     * @param subfolder Deployment category for file organization
     * @return didDeploy Whether a new deployment was made (false if already exists)
     * @return deployed Address of deployed contract
     * @dev Handles: version extraction, address computation, deployment, JSON tracking, verification
     */
    function __deploy(bytes memory creationCode, string memory subfolder) internal returns (bool, address) {
        if (!_isSetUp) revert SetupNotCalled();
        _assertBroadcastSenderMatchesDeployer();

        string memory versionAndVariant;
        bytes32 salt;
        address computed;
        bool shouldProcessStandardJson;
        string memory standardJsonInput;

        {
            string memory name;
            (name, versionAndVariant) = __getNameVersionAndVariant(creationCode);
            salt = _getSalt(versionAndVariant);

            bytes32 guardedSalt = _guardSalt(salt);

            // CREATE3 always uses CreateX as the deployer for the internal CREATE2 proxy
            computed = createX.computeCreate3Address(guardedSalt, address(createX));

            finalJsonLatest = vm.serializeAddress(jsonObjKeyAll, versionAndVariant, computed);
            if (computed.code.length != 0) {
                console.log(
                    unicode"⚠️[WARN] Skipping deployment, %s already deployed at %s", versionAndVariant, computed
                );
                return (false, computed);
            }

            (shouldProcessStandardJson, standardJsonInput) =
                _prepareStandardJsonInput(name, versionAndVariant, subfolder);
        }

        address deployed = _deployCreate3(salt, creationCode);
        if (computed != deployed) revert AddressMismatch(computed, deployed);
        console.log(unicode"✅[INFO] %s deployed at %s", versionAndVariant, computed);

        _hasNewDeployments = true;
        finalJson = vm.serializeAddress(jsonObjKeyDiff, versionAndVariant, computed);
        if (shouldProcessStandardJson) {
            _saveContractToStandardJsonInput(versionAndVariant, subfolder, standardJsonInput);
        }
        return (true, deployed);
    }

    /**
     * @notice Extract contract name and version from creation code
     * @param creationCode Contract creation code
     * @return name Contract name (extracted from version string)
     * @return versionAndVariant Full version string (e.g., "1.0.0-MyContract-cancun")
     * @dev Deploys contract to temporary address to call version() function
     *      Parses version string by splitting on "-" delimiter
     *      Pauses any active broadcast to prevent mock deployment from going on-chain
     *      Uses a VM snapshot to revert any constructor side effects
     */
    function __getNameVersionAndVariant(bytes memory creationCode)
        internal
        returns (string memory name, string memory versionAndVariant)
    {
        // Check cache first
        bytes32 codeHash = keccak256(creationCode);
        versionAndVariant = _versionCache[codeHash];
        if (bytes(versionAndVariant).length > 0) {
            name = _nameCache[codeHash];
            return (name, versionAndVariant);
        }

        // Pause any active broadcast to prevent mock deployment from going on-chain
        (VmSafe.CallerMode callerMode, address msgSender,) = vm.readCallers();
        bool wasBroadcast = callerMode == VmSafe.CallerMode.Broadcast;
        bool wasRecurrent = callerMode == VmSafe.CallerMode.RecurrentBroadcast;
        if (wasBroadcast || wasRecurrent) {
            console.log(
                unicode"⚠️[WARN] Version extraction during active broadcast. Use vm.startBroadcast(address) with --private-key CLI flag; hardcoding keys in scripts is not supported."
            );
            vm.stopBroadcast();
        }

        // Revert all side effects from the mock deployment after extracting the version.
        uint256 snapshotId = vm.snapshotState();

        uint256 constructorValue = _getDeployValues().constructorAmount;
        if (constructorValue > 0) {
            uint256 bal;
            assembly { bal := selfbalance() }
            if (bal < constructorValue) {
                revert VersionExtractionFailed(bal, constructorValue);
            }
        }
        address mockDeploymentAddress;
        assembly {
            mockDeploymentAddress := create(constructorValue, add(creationCode, 0x20), mload(creationCode))
        }
        if (mockDeploymentAddress == address(0)) {
            revert MockDeploymentFailed();
        }

        try IVersionable(mockDeploymentAddress).version() returns (string memory extractedVersion) {
            versionAndVariant = extractedVersion;
        } catch {
            vm.revertToState(snapshotId);
            revert VersionCallFailed();
        }

        bool reverted = vm.revertToState(snapshotId);
        if (!reverted) revert SnapshotRevertFailed();

        // Resume broadcast if it was active. Only address is available (not private key/hardware wallet).
        // Prank state is restored by vm.revertToState(), so only broadcast modes need explicit resume.
        if (wasBroadcast) {
            vm.broadcast(msgSender);
        } else if (wasRecurrent) {
            vm.startBroadcast(msgSender);
        }

        strings.slice memory slice = versionAndVariant.toSlice();
        strings.slice memory delimiter = string("-").toSlice();
        string[] memory parts = new string[](slice.count(delimiter) + 1);
        for (uint256 i = 0; i < parts.length; i++) {
            parts[i] = slice.split(delimiter).toString();
        }
        if (parts.length < 2) revert InvalidVersionFormat(versionAndVariant);
        name = parts[1];

        // Cache the results
        _versionCache[codeHash] = versionAndVariant;
        _nameCache[codeHash] = name;
    }

    /**
     * @notice Get EVM suffix, with caching
     * @return suffix The EVM suffix (e.g., "-cancun", "-shanghai", or "")
     * @dev Suffix is computed once in _setUp() and cached for efficiency
     */
    function _getEvmSuffix() internal view returns (string memory) {
        return _evmSuffix;
    }

    /**
     * @notice Get EVM suffix (public accessor for tests)
     * @return suffix The EVM suffix (e.g., "-cancun", "-shanghai", or "")
     * @dev Public wrapper for _getEvmSuffix() to allow external access in tests
     */
    function getEvmSuffix() public view returns (string memory) {
        return _getEvmSuffix();
    }

    /**
     * @notice Compute EVM suffix from foundry.toml
     * @return suffix The EVM suffix (e.g., "-cancun", "-shanghai", or "")
     * @dev Reads foundry.toml and extracts evm_version for the active profile
     */
    function _computeEvmSuffix() internal view returns (string memory) {
        string memory configPath = string.concat(vm.projectRoot(), "/foundry.toml");
        try vm.readFile(configPath) returns (string memory config) {
            string memory profile = vm.envOr("FOUNDRY_PROFILE", string("default"));
            string memory evmVersion = _readEvmVersionFromToml(config, profile);
            if (bytes(evmVersion).length > 0) {
                string memory suffix = string.concat("-", evmVersion);
                console.log(unicode"✓ EVM suffix from foundry.toml:", suffix);
                return suffix;
            }
        } catch Error(string memory reason) {
            console.log(unicode"✓ Failed to read foundry.toml:", reason);
        } catch (bytes memory lowLevelData) {
            console.log(unicode"✓ Failed to read foundry.toml (low-level error)");
            console.logBytes(lowLevelData);
        }

        console.log(unicode"✓ No EVM suffix (default)");
        return "";
    }

    /**
     * @notice Read evm_version from a TOML string for a given profile
     * @param toml The TOML config contents
     * @param profile The active Foundry profile (e.g., "default", "ci")
     * @return evmVersion The EVM version string (e.g., "cancun", "shanghai")
     * @dev Falls back to profile.default.evm_version, then root-level evm_version
     */
    function _readEvmVersionFromToml(string memory toml, string memory profile) internal view returns (string memory) {
        string memory profileKey = string.concat(".profile.", profile, ".evm_version");
        if (toml.keyExists(profileKey)) {
            return toml.readString(profileKey);
        }

        string memory defaultKey = ".profile.default.evm_version";
        if (toml.keyExists(defaultKey)) {
            return toml.readString(defaultKey);
        }

        string memory rootKey = ".evm_version";
        if (toml.keyExists(rootKey)) {
            return toml.readString(rootKey);
        }

        return "";
    }

    /**
     * @notice Prepare standard JSON input for verification (if enabled)
     * @param name Contract name
     * @param versionAndVariant Version string
     * @param subfolder Deployment category
     * @return shouldProcess Whether standard JSON processing is enabled
     * @return standardJsonInput Standard JSON input (empty when skipped)
     */
    function _prepareStandardJsonInput(string memory name, string memory versionAndVariant, string memory subfolder)
        internal
        returns (bool shouldProcess, string memory standardJsonInput)
    {
        shouldProcess = !_shouldSkipStandardJsonInput();
        if (!shouldProcess) {
            console.log(unicode"⚠️[WARN] SKIP_STANDARD_JSON_INPUT=true, skipping verification input generation.");
            standardJsonInput = "";
        } else {
            standardJsonInput = _generateStandardJsonInput(name);
            if (bytes(standardJsonInput).length == 0) {
                shouldProcess = false; // Skip if FFI failed
            } else {
                _checkStandardJsonInput(versionAndVariant, subfolder, standardJsonInput);
            }
        }

        return (shouldProcess, standardJsonInput);
    }

    /**
     * @notice Determine whether standard JSON input processing should be skipped
     * @return skip True if standard JSON processing should be skipped
     * @dev Virtual to allow test helpers or advanced scripts to override behavior safely
     */
    function _shouldSkipStandardJsonInput() internal view virtual returns (bool skip) {
        return _SKIP_STANDARD_JSON_INPUT;
    }

    /**
     * @notice Deploy using CREATE3 with optional atomic initialization
     * @param salt Salt for CREATE3 deployment
     * @param creationCode Contract creation code
     * @return deployed Address of the deployed contract
     * @dev Solidity 0.8.x uses checked arithmetic.
     */
    function _deployCreate3(bytes32 salt, bytes memory creationCode) internal returns (address deployed) {
        bytes memory initData = _getPostDeployInitData();
        ICreateX.Values memory values = _getDeployValues();

        // Outside broadcast (e.g., tests), prank as _deployer to match msg.sender used in _guardSalt.
        (VmSafe.CallerMode callerMode,,) = vm.readCallers();
        bool needsPrank =
            callerMode != VmSafe.CallerMode.Broadcast && callerMode != VmSafe.CallerMode.RecurrentBroadcast;

        if (initData.length == 0) {
            if (values.initCallAmount > 0) {
                revert InitAmountWithoutInitData(values.initCallAmount);
            }
            if (needsPrank) vm.prank(_deployer);
            return createX.deployCreate3{value: values.constructorAmount}(salt, creationCode);
        }

        if (needsPrank) vm.prank(_deployer);
        return createX.deployCreate3AndInit{value: values.constructorAmount + values.initCallAmount}(
            salt, creationCode, initData, values
        );
    }

    /**
     * @notice Get Unix username for deployment tracking
     * @return Username from `whoami` command, or "unknown" if FFI is disabled
     * @dev Uses tryFfi to gracefully handle FFI being disabled.
     *      Trims trailing newline/carriage return characters from FFI output.
     */
    function __getUnixHost() private returns (string memory) {
        string[] memory inputs = new string[](1);
        inputs[0] = "whoami";

        // Use try/catch because vm.tryFfi reverts when FFI is disabled at config level
        try vm.tryFfi(inputs) returns (VmSafe.FfiResult memory result) {
            if (result.exitCode == 0 && result.stdout.length > 0) {
                bytes memory output = result.stdout;
                uint256 len = output.length;
                // Trim trailing \n (0x0a) and \r (0x0d)
                while (len > 0 && (output[len - 1] == 0x0a || output[len - 1] == 0x0d)) {
                    len--;
                }
                // Adjust length in-place using assembly
                assembly {
                    mstore(output, len)
                }
                return string(output);
            }
        } catch {
            // FFI disabled at config level or command failed
        }
        return "unknown";
    }

    /**
     * @notice Generate standard JSON input for contract verification
     * @param contractName Name of the contract
     * @return JSON string for verification
     * @dev Uses forge verify-contract --show-standard-json-input via FFI.
     *      Override this in tests or restricted environments if needed.
     *      Uses _getContractPath() to support fully-qualified contract identifiers.
     */
    function _generateStandardJsonInput(string memory contractName) internal virtual returns (string memory) {
        string memory contractIdentifier;
        string memory path = _getContractPath();
        if (bytes(path).length > 0) {
            contractIdentifier = string.concat(path, ":", contractName);
        } else {
            contractIdentifier = contractName;
        }

        string[] memory inputs = new string[](5);
        inputs[0] = "forge";
        inputs[1] = "verify-contract";
        inputs[2] = "0x0000000000000000000000000000000000000000";
        inputs[3] = contractIdentifier;
        inputs[4] = "--show-standard-json-input";

        // Use try/catch because vm.tryFfi reverts when FFI is disabled at config level
        try vm.tryFfi(inputs) returns (VmSafe.FfiResult memory result) {
            if (result.exitCode == 0) {
                return string(result.stdout);
            }
            console.log(
                unicode"⚠️[WARN] Failed to generate standard JSON input for %s. Enable FFI or set SKIP_STANDARD_JSON_INPUT=true.",
                contractName
            );
        } catch {
            // FFI disabled at config level
            console.log(
                unicode"⚠️[WARN] FFI disabled. Skipping standard JSON input for %s. Set SKIP_STANDARD_JSON_INPUT=true to suppress.",
                contractName
            );
        }
        return "";
    }

    /**
     * @notice Save contract verification JSON to file
     * @param versionAndVariant Version string for file naming
     * @param subfolder Deployment category
     * @param standardJsonInput JSON content to save
     * @dev Saves to deployments/{subfolder}/standard-json-inputs/{version}.json
     *      Appends timestamp if file exists and FORCE_DEPLOY is true
     */
    function _saveContractToStandardJsonInput(
        string memory versionAndVariant,
        string memory subfolder,
        string memory standardJsonInput
    ) internal virtual {
        string memory outputDir = string.concat(vm.projectRoot(), "/deployments/", subfolder, "/standard-json-inputs");
        vm.createDir(outputDir, true);

        string memory outputPath = string.concat(outputDir, "/", versionAndVariant, ".json");

        if (vm.isFile(outputPath) && _FORCE_DEPLOY) {
            outputPath = string.concat(
                vm.projectRoot(),
                "/deployments/",
                subfolder,
                "/standard-json-inputs/",
                versionAndVariant,
                "-",
                unixTime,
                ".json"
            );
            console.log(
                unicode"✅[INFO] Standard JSON input for %s saved with timestamp due to FORCE_DEPLOY",
                versionAndVariant
            );
        } else {
            console.log(unicode"✅[INFO] Standard JSON input for %s saved", versionAndVariant);
        }

        vm.writeFile(outputPath, standardJsonInput);
    }

    /**
     * @notice Check if verification JSON exists and matches
     * @param versionAndVariant Version string
     * @param subfolder Deployment category
     * @param standardJsonInput JSON content to compare
     * @dev Reverts if file exists with different content and FORCE_DEPLOY is false
     */
    function _checkStandardJsonInput(
        string memory versionAndVariant,
        string memory subfolder,
        string memory standardJsonInput
    ) internal view virtual {
        string memory outputPath = string.concat(
            vm.projectRoot(), "/deployments/", subfolder, "/standard-json-inputs/", versionAndVariant, ".json"
        );

        if (vm.isFile(outputPath)) {
            console.log(
                unicode"⏳[INFO] Verification file for %s already exists, checking for changes...", versionAndVariant
            );
            string memory existingOutput = vm.readFile(outputPath);
            if (keccak256(abi.encodePacked(existingOutput)) != keccak256(abi.encodePacked(standardJsonInput))) {
                if (!_FORCE_DEPLOY) {
                    revert StandardJsonInputMismatch(versionAndVariant);
                } else {
                    console.log(
                        unicode"⚠️[WARN] FORCE_DEPLOY=true, proceeding with deployment despite different standard JSON input for %s",
                        versionAndVariant
                    );
                }
            }
        }
    }
}

/**
 * @title _LatestJsonParser
 * @notice Temporary helper contract for parsing -latest.json files
 * @dev Deployed transiently by DeployHelper._loadExistingLatestEntries() to enable
 *      try/catch error handling without using address(this), which Foundry 1.5.x
 *      blocks in script contracts. The contract is created via CREATE and discarded
 *      after use (no persistent state).
 */
contract _LatestJsonParser {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function parse(string calldata json) external pure returns (string[] memory keys, address[] memory addrs) {
        keys = vm.parseJsonKeys(json, "$");
        addrs = new address[](keys.length);
        for (uint256 i = 0; i < keys.length; i++) {
            string memory keyPath = string.concat("$['", keys[i], "']");
            addrs[i] = vm.parseJsonAddress(json, keyPath);
        }
    }
}
