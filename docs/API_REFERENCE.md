# API Reference

Complete API documentation for foundry-deployer.

## Table of Contents

- [DeployHelper](#deployhelper)
  - [Setup Methods](#setup-methods)
  - [Deployment Methods](#deployment-methods)
  - [Utility Methods](#utility-methods)
  - [Virtual Methods](#virtual-methods)
  - [Public Variables](#public-variables)
- [CreateXHelper](#createxhelper)
- [Versionable](#versionable)
- [IVersionable Interface](#iversionable-interface)
- [Environment Variables](#environment-variables)

---

## DeployHelper

`DeployHelper` is the base contract for all deployment scripts. Inherit from it and override virtual methods to customize behavior.

```solidity
import {DeployHelper} from "foundry-deployer/DeployHelper.sol";

contract MyDeploy is DeployHelper {
    function setUp() public override {
        _setUp("category");
    }

    function run() public {
        // Your deployment logic
    }
}
```

### Setup Methods

#### `setUp()`

```solidity
function setUp() public virtual
```

**Must be overridden.** Call `_setUp()` with your deployment category.

**Example:**
```solidity
function setUp() public override {
    _setUp("production");
}
```

#### `_setUp(string memory subfolder)`

```solidity
function _setUp(string memory subfolder) internal withCreateX
```

Initialize the deployment helper with a category name.

**Parameters:**
- `subfolder`: Deployment category for organizing files (e.g., "production", "staging")

**What it does:**
- Reads environment variables from `.env`
- Sets up JSON file paths
- Initializes CreateX integration

**Example:**
```solidity
_setUp("my-contracts");
// Creates deployments in: deployments/my-contracts/
```

---

### Deployment Methods

#### `deploy(bytes memory creationCode)`

```solidity
function deploy(bytes memory creationCode) internal returns (address deployed)
```

Deploy a contract using CREATE3.

**Parameters:**
- `creationCode`: Contract creation bytecode (use `type(MyContract).creationCode`)

**Returns:**
- `deployed`: Address of the deployed contract

**Behavior:**
- Skips deployment if contract already exists at computed address
- Logs deployment status
- Tracks deployment in JSON
- Generates verification files
- Uses atomic deploy+init via CreateX's `deployCreate3AndInit` to prevent front-running

**✅ Security Note:**

Deployment and initialization now happen atomically in a single transaction using CreateX's `deployCreate3AndInit`. This prevents front-running attacks where an attacker could claim ownership between deployment and initialization.

**Example:**
```solidity
address myContract = deploy(type(MyContract).creationCode);
```

#### `__deploy(bytes memory creationCode, string memory subfolder)`

```solidity
function __deploy(bytes memory creationCode, string memory subfolder)
    internal returns (bool didDeploy, address deployed)
```

Core deployment function with additional control.

**Parameters:**
- `creationCode`: Contract creation bytecode
- `subfolder`: Deployment category (usually `deploymentCategory`)

**Returns:**
- `didDeploy`: `true` if new deployment, `false` if already deployed
- `deployed`: Address of the deployed contract

**Example:**
```solidity
(bool isNew, address addr) = __deploy(
    type(MyContract).creationCode,
    "production"
);

if (isNew) {
    // Initialize new deployment
    MyContract(addr).initialize();
}
```

#### `computeDeploymentAddress(bytes memory creationCode)`

```solidity
function computeDeploymentAddress(bytes memory creationCode)
    public returns (address predicted)
```

Compute deployment address without deploying.

**Parameters:**
- `creationCode`: Contract creation bytecode

**Returns:**
- `predicted`: Predicted deployment address

**Note:** Requires `_setUp()` to be called first. Not `view` because it creates a temporary contract to extract version.

**Example:**
```solidity
address predictedAddr = computeDeploymentAddress(
    type(MyContract).creationCode
);
console.log("Will deploy to:", predictedAddr);

address deployed = deploy(type(MyContract).creationCode);
assert(deployed == predictedAddr);
```

---

### Utility Methods

#### `_afterAll()`

```solidity
function _afterAll() internal virtual
```

Save deployment artifacts to JSON files. Call at the end of your `run()` function.

**Behavior:**
- Only saves if `_deployer` matches `ALLOWED_DEPLOYMENT_SENDER`
- Writes timestamped JSON file if there are new deployments
- Updates `-latest.json` file only when new deployments occur

**Example:**
```solidity
function run() public {
    address deployed = deploy(type(MyContract).creationCode);
    _afterAll(); // Save deployment artifacts
}
```

#### `_checkChainAndSetOwner(address instance)`

```solidity
function _checkChainAndSetOwner(address instance) internal virtual
```

Transfer ownership to production owner on mainnet chains.

**Parameters:**
- `instance`: Contract address to transfer ownership

**Behavior:**
- Checks if current chain ID is in `MAINNET_CHAIN_IDS`
- If mainnet: transfers ownership to `PROD_OWNER`
- If testnet: skips transfer (deployer retains ownership)
- Skips if owner already set to `PROD_OWNER`

**Example:**
```solidity
address deployed = deploy(type(MyContract).creationCode);
_checkChainAndSetOwner(deployed); // Transfer on mainnet only
```

#### `_getSalt(string memory version)`

```solidity
function _getSalt(string memory version) internal view virtual returns (bytes32)
```

Generate CREATE3 salt from version string.

**Parameters:**
- `version`: Version string (e.g., "1.0.0-MyContract-cancun")

**Returns:**
- Salt for CREATE3 deployment

**Default Implementation:**
```solidity
bytes1 crosschainProtectionFlag = bytes1(0x00);
bytes11 randomSeed = bytes11(keccak256(abi.encode(version)));
return bytes32(abi.encodePacked(_deployer, crosschainProtectionFlag, randomSeed));
```

**Override for custom salt logic:**
```solidity
function _getSalt(string memory version) internal view override returns (bytes32) {
    // Include chain ID in salt for per-chain addresses
    return keccak256(abi.encodePacked(msg.sender, version, block.chainid));
}
```

---

### Virtual Methods

These methods can be overridden to customize deployment behavior.

#### `_getPostDeployInitData()`

```solidity
function _getPostDeployInitData() internal virtual returns (bytes memory)
```

Get initialization data for atomic deploy+init.

**Returns:**
- Calldata to execute after deployment (executed atomically via `deployCreate3AndInit`)

**Default Implementation:**
```solidity
return abi.encodeWithSignature("initializeOwner(address)", _deployer);
```

**Override to skip initialization:**
```solidity
function _getPostDeployInitData() internal pure override returns (bytes memory) {
    return ""; // Empty bytes = skip init, use plain deployCreate3
}
```

**Override for custom initialization:**
```solidity
function _getPostDeployInitData() internal view override returns (bytes memory) {
    return abi.encodeWithSignature("initialize(address,uint256)", customOwner, initialValue);
}
```

#### `_getDeployValues()`

```solidity
function _getDeployValues() internal virtual returns (ICreateX.Values memory)
```

Get ETH values to send during deployment.

**Returns:**
- `ICreateX.Values` struct with `constructorAmount` and `initCallAmount`

**Default Implementation:**
```solidity
return ICreateX.Values({constructorAmount: 0, initCallAmount: 0});
```

**Override to send ETH during deployment:**
```solidity
function _getDeployValues() internal pure override returns (ICreateX.Values memory) {
    return ICreateX.Values({
        constructorAmount: 1 ether,  // Send to constructor
        initCallAmount: 0.5 ether    // Send to init call
    });
}
```

#### `_initializeOwnerAfterDeploy(address deployed)`

```solidity
function _initializeOwnerAfterDeploy(address deployed) internal virtual
```

**⚠️ DEPRECATED:** This hook is now a no-op. Override `_getPostDeployInitData()` instead.

The old hook design was incompatible with atomic deploy+init since the deployed address doesn't exist yet at call time. This function is kept for backwards compatibility but does nothing by default.

**Migration:** If you previously overrode this function, migrate to `_getPostDeployInitData()`:

**Old approach (deprecated):**
```solidity
function _initializeOwnerAfterDeploy(address deployed) internal override {
    // Skip initialization
}
```

**New approach:**
```solidity
function _getPostDeployInitData() internal pure override returns (bytes memory) {
    return ""; // Return empty bytes to skip init
}
```

#### `_setUp(string memory subfolder)`

Already covered in [Setup Methods](#_setupstring-memory-subfolder).

#### `_afterAll()`

Already covered in [Utility Methods](#_afterall).

#### `_checkChainAndSetOwner(address instance)`

Already covered in [Utility Methods](#_checkchainandsetowneraddress-instance).

#### `_getSalt(string memory version)`

Already covered in [Utility Methods](#_getsaltstring-memory-version).

---

### Public Variables

#### Deployment Tracking

```solidity
string public jsonPath;           // Timestamped JSON file path
string public jsonPathLatest;     // Latest JSON file path (-latest.json)
string public deploymentCategory; // Deployment category (subfolder)
string public unixTime;           // Deployment timestamp
```

#### JSON Serialization

```solidity
string public jsonObjKeyDiff;    // Key for new deployments
string public jsonObjKeyAll;     // Key for all deployments
string public finalJson;         // Serialized new deployments
string public finalJsonLatest;   // Serialized all deployments
```

#### Environment Variables (Internal)

```solidity
address internal _PROD_OWNER;              // Production owner
uint256[] internal _MAINNET_CHAIN_IDS;     // Mainnet chain IDs
bool internal _FORCE_DEPLOY;               // Force redeploy flag
address internal _ALLOWED_DEPLOYMENT_SENDER; // Allowed saver address
```

---

## CreateXHelper

```solidity
import {CreateXHelper} from "foundry-deployer/CreateXHelper.sol";
```

### Overview

`CreateXHelper` provides CreateX factory setup and verification logic for Foundry scripts. It automatically ensures CreateX is available on the target network by etching it if missing.

### Key Features

- Automatic CreateX deployment detection
- Etching CreateX on local/test networks where it's missing
- CreateX code hash verification
- `withCreateX` modifier for ensuring setup before deployment

### Constants

```solidity
address internal constant CREATEX_ADDRESS = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;
bytes32 internal constant CREATEX_EXTCODEHASH = 0xbd8a7ea8cfca7b4e5f5041d7d4b17bc317c5ce42cfbc42066a00cf26b43eb53f;
bytes32 internal constant EMPTY_ACCOUNT_HASH = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
ICreateX internal constant createX = ICreateX(CREATEX_ADDRESS);
```

### Modifier

```solidity
modifier withCreateX()
```

Ensures CreateX is deployed before executing the function. Automatically etches CreateX on chains where it's missing (using `vm.etch` - only works in Foundry context).

### Custom Errors

```solidity
error CreateXDeploymentFailed();
error UnexpectedCodeAtCreateXAddress();
```

---

## Versionable Abstract Contract

```solidity
import {Versionable} from "foundry-deployer/Versionable.sol";
```

### Overview

`Versionable` is an abstract contract that provides version management with optional EVM suffix support.

### Constructor

```solidity
constructor(string memory evmSuffix_)
```

Accepts an EVM version suffix (e.g., `""`, `"-cancun"`, `"-shanghai"`).

### Required Override

```solidity
function _baseVersion() internal pure virtual returns (string memory);
```

Override this function to return your contract's base version string.

### Implementation Example

```solidity
import {Versionable} from "foundry-deployer/Versionable.sol";
import {Ownable} from "solady/auth/Ownable.sol";

contract MyContract is Versionable, Ownable {
    constructor(string memory evmSuffix_) Versionable(evmSuffix_) {
        // Owner will be initialized after deployment by DeployHelper
    }

    function initializeOwner(address _owner) external {
        require(owner() == address(0), "Already initialized");
        _initializeOwner(_owner);
    }

    function _baseVersion() internal pure override returns (string memory) {
        return "1.0.0-MyContract";
    }
}
```

### Deployment Example

```solidity
// EVM suffix is auto-detected from foundry.toml
bytes memory creationCode = abi.encodePacked(
    type(MyContract).creationCode,
    abi.encode(_getEvmSuffix())
);
address deployed = deploy(creationCode);
```

### Version Results

The EVM suffix is automatically detected from `foundry.toml` using the active `FOUNDRY_PROFILE` (falling back to `profile.default`, then root-level `evm_version`):

- No `evm_version` in config: Returns `"1.0.0-MyContract"`
- `evm_version = "cancun"`: Returns `"1.0.0-MyContract-cancun"`
- `evm_version = "shanghai"`: Returns `"1.0.0-MyContract-shanghai"`

---

## IVersionable Interface

```solidity
import {IVersionable} from "foundry-deployer/interfaces/IVersionable.sol";
```

### Interface Definition

```solidity
interface IVersionable {
    function version() external view returns (string memory);
}
```

### Implementation

The recommended way to implement `IVersionable` is to extend the `Versionable` abstract contract:

```solidity
contract MyContract is Versionable, Ownable {
    constructor(string memory evmSuffix_) Versionable(evmSuffix_) {
        // Owner will be initialized after deployment by DeployHelper
    }

    function initializeOwner(address _owner) external {
        require(owner() == address(0), "Already initialized");
        _initializeOwner(_owner);
    }

    function _baseVersion() internal pure override returns (string memory) {
        return "1.0.0-MyContract";
    }
}
```

### Version String Format

Follow this format for consistency:

```
{major}.{minor}.{patch}-{ContractName}{evmSuffix}
```

**Examples:**
- `1.0.0-MyContract`
- `2.3.1-TokenVault-shanghai`
- `0.1.0-BetaFeature-cancun-beta`

---

## Environment Variables

Configure these in your `.env` file.

### Required Variables

#### `PROD_OWNER`

```bash
PROD_OWNER=0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0
```

**Type:** `address`

**Description:** Address that will own contracts on mainnet chains. Used by `_checkChainAndSetOwner()`.

**Behavior:**
- On mainnet (chain ID in `MAINNET_CHAIN_IDS`): ownership transferred to this address
- On testnet: deployer retains ownership

---

#### `MAINNET_CHAIN_IDS`

```bash
MAINNET_CHAIN_IDS=1,56,137,8453
```

**Type:** `uint256[]` (comma-separated)

**Description:** List of chain IDs considered "mainnet" where ownership transfer occurs.

**Common Values:**
- `1` - Ethereum Mainnet
- `56` - BNB Chain
- `137` - Polygon
- `8453` - Base
- `42161` - Arbitrum One
- `10` - Optimism

---

#### `ALLOWED_DEPLOYMENT_SENDER`

```bash
ALLOWED_DEPLOYMENT_SENDER=0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0
```

**Type:** `address`

**Description:** Only this address can save deployment JSON files. Should match your deployer address.

**Security:** Prevents unauthorized modification of deployment records.

---

### Optional Variables

#### `FORCE_DEPLOY`

```bash
FORCE_DEPLOY=false
```

**Type:** `bool`

**Default:** `false`

**Description:** Allow deployment to proceed when the stored standard JSON input differs, and save a timestamped verification input.
It does not bypass the "already deployed" address check.

**Use Cases:**
- Testing deployment scripts
- Accepting verification input changes while keeping deterministic addresses

---

#### `SKIP_STANDARD_JSON_INPUT`

```bash
SKIP_STANDARD_JSON_INPUT=false
```

**Type:** `bool`

**Default:** `false`

**Description:** Skips standard JSON input generation, comparison, and saving. This bypasses the FFI call used for verification inputs.

**Use Cases:**
- Restricted CI or sandboxed environments where FFI is unavailable
- Offline workflows
- Faster test runs when verification artifacts are not needed

---

## Advanced Usage

### Custom Deployment Logic

Override virtual methods for custom behavior:

```solidity
contract CustomDeploy is DeployHelper {
    // Custom salt generation
    function _getSalt(string memory version)
        internal view override returns (bytes32)
    {
        // Include chain ID for per-chain addresses
        return keccak256(abi.encodePacked(
            msg.sender,
            version,
            block.chainid
        ));
    }

    // Custom ownership transfer
    function _checkChainAndSetOwner(address instance)
        internal override
    {
        // Transfer ownership on all chains, not just mainnet
        vm.broadcast();
        Ownable(instance).transferOwnership(_PROD_OWNER);
    }

    // Custom post-deployment logic
    function _afterAll() internal override {
        // Call parent to save JSON
        super._afterAll();

        // Custom logic
        console.log("Deployment complete!");
    }
}
```

You can also override `_shouldSkipStandardJsonInput()` to bypass standard JSON generation/checks programmatically (for example, in tests or restricted CI environments).

### Conditional Deployment

Deploy only if certain conditions are met:

```solidity
function run() public {
    // Check if contract should be deployed
    if (shouldDeploy()) {
        address deployed = deploy(type(MyContract).creationCode);
        _checkChainAndSetOwner(deployed);
    }

    _afterAll();
}

function shouldDeploy() internal view returns (bool) {
    // Custom logic
    return block.chainid != 1; // Skip Ethereum mainnet
}
```

### Multi-Stage Deployments

Deploy contracts in stages with dependencies:

```solidity
function run() public {
    // Stage 1: Core contracts
    address token = deploy(type(Token).creationCode);
    address vault = deploy(type(Vault).creationCode);

    // Stage 2: Initialize
    vm.startBroadcast();
    Vault(vault).setToken(token);
    vm.stopBroadcast();

    // Stage 3: Dependent contracts
    address router = deploy(
        abi.encodePacked(
            type(Router).creationCode,
            abi.encode(token, vault)
        )
    );

    // Stage 4: Ownership transfer
    _checkChainAndSetOwner(token);
    _checkChainAndSetOwner(vault);
    _checkChainAndSetOwner(router);

    _afterAll();
}
```

### Deployment with Constructor Arguments

```solidity
function run() public {
    // Encode constructor arguments
    bytes memory creationCode = abi.encodePacked(
        type(MyContract).creationCode,
        abi.encode(
            arg1,  // constructor argument 1
            arg2,  // constructor argument 2
            arg3   // constructor argument 3
        )
    );

    address deployed = deploy(creationCode);
    _checkChainAndSetOwner(deployed);
    _afterAll();
}
```

**Note:** Each unique constructor argument set creates a different deployment address.

---

## Best Practices

1. **Always implement IVersionable**: Ensures version tracking works correctly
2. **Use semantic versioning**: Follow `major.minor.patch` format
3. **Call _afterAll() last**: Save artifacts after all deployments complete
4. **Test locally first**: Use Anvil to test deployment scripts
5. **Document custom overrides**: Comment why you're overriding virtual methods
6. **Validate addresses**: Use `computeDeploymentAddress()` to verify before deploying
7. **Handle errors gracefully**: Use try-catch for initialization calls
8. **Version on bytecode changes**: Increment version when constructor args or code changes

---

## Error Handling

### Common Errors

**"Computed address mismatch"**
- Cause: CREATE3 deployment failed
- Solution: Check salt generation and CreateX is properly deployed

**"Already deployed"**
- Cause: Contract exists at computed address
- Solution: Change the version (deterministic deployments cannot overwrite existing code)

**"Skipping deployment save"**
- Cause: Sender doesn't match `ALLOWED_DEPLOYMENT_SENDER`
- Solution: Set correct address in `.env`

**"FFI disabled"**
- Cause: `ffi = true` not set in `foundry.toml`
- Solution: Enable FFI in config, or set `SKIP_STANDARD_JSON_INPUT=true`

---

## See Also

- [Getting Started Guide](./GETTING_STARTED.md)
- [Examples](../script/examples/)
