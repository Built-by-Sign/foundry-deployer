# Getting Started with Foundry Deployer

## Prerequisites

- [Foundry](https://getfoundry.sh/) installed
- Basic understanding of Foundry scripts
- A Solidity project with Foundry initialized

## Installation

### Step 1: Install the Package

```bash
forge install EthSign/foundry-deployer
```

### Step 2: Update Remappings

Foundry should automatically detect the remapping. Verify by checking `remappings.txt`:

```
foundry-deployer/=lib/foundry-deployer/src/
```

If not present, add it manually.

### Step 3: Install Dependencies

The package has peer dependencies that need to be installed:

```bash
forge install Vectorized/solady
```

## Your First Deployment

Let's create a simple contract and deploy it using foundry-deployer.

### Step 1: Create a Versioned Contract

Create `src/MyFirstContract.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Versionable} from "foundry-deployer/Versionable.sol";
import {Ownable} from "solady/auth/Ownable.sol";

contract MyFirstContract is Versionable, Ownable {
    uint256 public value;

    constructor(string memory evmSuffix_, address owner_) Versionable(evmSuffix_) {
        _initializeOwner(owner_);
    }

    function setValue(uint256 _value) external onlyOwner {
        value = _value;
    }

    function _baseVersion() internal pure override returns (string memory) {
        return "1.0.0-MyFirstContract";
    }
}
```

### Step 2: Create a Deployment Script

Create `script/DeployMyFirstContract.s.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DeployHelper} from "foundry-deployer/DeployHelper.sol";
import {MyFirstContract} from "../src/MyFirstContract.sol";

contract DeployMyFirstContract is DeployHelper {
    function setUp() public override {
        // Use explicit deployer address that matches broadcast sender
        _setUp("my-project", msg.sender);
    }

    function run() public {
        vm.startBroadcast();

        // Deploy using CREATE3
        // EVM suffix is auto-detected from foundry.toml
        // Owner is set in the constructor — no atomic init needed
        bytes memory creationCode = abi.encodePacked(
            type(MyFirstContract).creationCode,
            abi.encode(_getEvmSuffix(), msg.sender)
        );
        address deployed = deploy(creationCode);

        // Transfer ownership on mainnet (optional)
        _checkChainAndSetOwner(deployed);

        vm.stopBroadcast();

        // Save deployment artifacts
        _afterAll();
    }
}
```

### Step 3: Configure Environment Variables

Create or update your `.env` file:

```bash
# Required for deployment
PRIVATE_KEY=0x... # Your deployer private key

# Required for foundry-deployer
PROD_OWNER=0x... # Address to own contracts on mainnet
MAINNET_CHAIN_IDS=1,56,137,8453 # Comma-separated mainnet chain IDs
ALLOWED_DEPLOYMENT_SENDER=0x... # Your deployer address (matches private key)

# Optional
FORCE_DEPLOY=false # Allow verification JSON changes (does not redeploy existing code)
SKIP_STANDARD_JSON_INPUT=false # Skip standard JSON generation/checks (restricted CI/offline)
```

**Environment Variable Details:**

- `PROD_OWNER`: The address that will own contracts on mainnet chains. On testnets, the deployer retains ownership.
- `MAINNET_CHAIN_IDS`: Comma-separated list of chain IDs considered "mainnet" where ownership transfer occurs.
- `ALLOWED_DEPLOYMENT_SENDER`: Only this address can save deployment JSON files. Should match your deployer address.
- `FORCE_DEPLOY`: Allows deployment to proceed when the stored standard JSON input differs. It does not bypass the "already deployed" check.
- `SKIP_STANDARD_JSON_INPUT`: Skips verification input generation/checking/saving. Useful when FFI is disabled or unavailable.

**EVM Version Suffix:**

The EVM version suffix is automatically detected from `foundry.toml` using the active `FOUNDRY_PROFILE` (falling back to `profile.default`, then root-level `evm_version`):

```toml
# foundry.toml
[profile.default]
evm_version = "cancun"  # Auto-appends "-cancun" to version strings
```

This ensures the version string always matches the actual compiler EVM version.

Load the environment variables:

```bash
source .env
```

### Step 4: Deploy to Local Network

First, test on a local network:

```bash
# Start Anvil
anvil

# In another terminal, deploy
forge script script/DeployMyFirstContract.s.sol \
  --rpc-url http://localhost:8545 \
  --broadcast
```

### Step 5: Check Deployment Artifacts

After deployment, check the generated files:

```bash
ls deployments/my-project/
```

You should see:
- `31337-latest.json` - Latest deployment addresses (Anvil chain ID)
- `31337-<username>-<timestamp>.json` - Timestamped deployment record
- `standard-json-inputs/` - Verification data for Etherscan

View the deployment:

```bash
cat deployments/my-project/31337-latest.json
```

Output:
```json
{
  "1.0.0-MyFirstContract": "0x..."
}
```

### Step 6: Deploy to Testnet

Deploy to Sepolia testnet:

```bash
forge script script/DeployMyFirstContract.s.sol \
  --rpc-url https://eth-sepolia.g.alchemy.com/v2/$ALCHEMY_KEY \
  --broadcast \
  --verify
```

### Computing Addresses in Advance

```solidity
contract DeployMyFirstContract is DeployHelper {
    function setUp() public override {
        _setUp("my-project", msg.sender);
    }

    function run() public {
        bytes memory creationCode = abi.encodePacked(
            type(MyFirstContract).creationCode,
            abi.encode(_getEvmSuffix(), msg.sender)
        );

        vm.startBroadcast();

        // Compute address before deploying
        address predicted = computeDeploymentAddress(creationCode);
        console.log("Will deploy to:", predicted);

        // Deploy
        address deployed = deploy(creationCode);
        require(predicted == deployed, "Address mismatch!");

        vm.stopBroadcast();
        _afterAll();
    }
}
```

## Working with EVM Versions

### Version String Result

```
Without EVM version: "1.0.0-MyFirstContract"
With shanghai:       "1.0.0-MyFirstContract-shanghai"
With cancun:         "1.0.0-MyFirstContract-cancun"
```

## Multi-Contract Deployments

Deploy multiple contracts in a single script:

```solidity
contract DeployMultiple is DeployHelper {
    function setUp() public override {
        _setUp("my-project", msg.sender);
    }

    function run() public {
        vm.startBroadcast();

        // Deploy contracts
        bytes memory tokenCode = abi.encodePacked(type(Token).creationCode, abi.encode(_getEvmSuffix()));
        bytes memory vaultCode = abi.encodePacked(type(Vault).creationCode, abi.encode(_getEvmSuffix()));
        bytes memory routerCode = abi.encodePacked(type(Router).creationCode, abi.encode(_getEvmSuffix()));

        address token = deploy(tokenCode);
        address vault = deploy(vaultCode);
        address router = deploy(routerCode);

        // Initialize with cross-references
        Vault(vault).setToken(token);
        Router(router).initialize(token, vault);

        // Transfer ownership for all
        _checkChainAndSetOwner(token);
        _checkChainAndSetOwner(vault);
        _checkChainAndSetOwner(router);

        vm.stopBroadcast();

        // Save all deployments
        _afterAll();
    }
}
```

> **Note:** If `setToken` and `initialize` are `onlyOwner` functions, you need ownership
> established first. Either use constructor-based ownership (pass `_deployer` as a constructor
> argument) or override `_getPostDeployInitData()` for atomic initialization.
> See `script/examples/MultiContract.s.sol` for a complete example with atomic init.

All three contracts will be saved in the same JSON file with their respective versions.

## Troubleshooting

### Contract Already Deployed

```
⚠️[WARN] Skipping deployment, 1.0.0-MyFirstContract already deployed at 0x...
```

**Solution**: This is normal. CREATE3 deployments are deterministic. To deploy new code, change the version number (which changes the salt and address). `FORCE_DEPLOY=true` does not bypass an existing deployment.

### Deployment Not Saved

```
⚠️[WARN] Skipping deployment save. Deployer 0x... does not match allowed sender 0x...
```

**Solution**: Set `ALLOWED_DEPLOYMENT_SENDER` in your `.env` to match your deployer address.

### FFI Disabled

```
Error: FFI is disabled
```

**Solution**: Enable FFI in `foundry.toml`, or set `SKIP_STANDARD_JSON_INPUT=true` to bypass verification input generation:
```toml
ffi = true
```

### Filesystem Permissions

```
Error: Cannot write to deployments/
```

**Solution**: Add filesystem permissions in `foundry.toml`:
```toml
fs_permissions = [{ access = "read-write", path = "./deployments/" }]
```

## Next Steps

- [API Reference](./API_REFERENCE.md)
- [GitHub Actions Integration](../README.md#github-actions-integration)
- [Custom Deployment Logic](./API_REFERENCE.md#custom-deployment-logic)

## Security Considerations

### Atomic Deploy+Init Protection

**Opt-in Protection:** For contracts that use post-deploy initialization (e.g., `initializeOwner(address)`), Foundry Deployer supports atomic deploy+init via CreateX's `deployCreate3AndInit`. This prevents front-running attacks where an attacker could claim ownership between deployment and initialization.

**Default behavior:** Plain `deployCreate3` with no post-deploy init call. This is safe for contracts that set their owner in the constructor.

**Enable atomic init** by overriding `_getPostDeployInitData()`:
```solidity
contract AtomicDeploy is DeployHelper {
    function _getPostDeployInitData() internal virtual override returns (bytes memory) {
        return abi.encodeWithSignature("initializeOwner(address)", _deployer);
    }
}
```

**How it works:**
1. Deployment and `initializeOwner()` call happen in one transaction
2. No window for attackers to intercept ownership
3. Plain `deployCreate3` is used when `_getPostDeployInitData()` returns empty bytes (the default)

### Custom Initialization

**Custom init data** (different initialization logic):
```solidity
contract CustomDeploy is DeployHelper {
    function _getPostDeployInitData() internal view override returns (bytes memory) {
        return abi.encodeWithSignature("initialize(address,uint256)", customOwner, initialValue);
    }
}
```

**Send ETH during deployment** (if contract constructor or init call is payable):
```solidity
contract CustomDeploy is DeployHelper {
    function _getDeployValues() internal pure override returns (ICreateX.Values memory) {
        return ICreateX.Values({
            constructorAmount: 1 ether,  // ETH to constructor
            initCallAmount: 0            // ETH to init call
        });
    }
}
```

### Best Practices

1. **Test on testnet first**: Always verify your deployment flow before mainnet
2. **Use private RPCs for sensitive deployments**: Additional protection layer
3. **Verify initialization**: Check that ownership is correctly set after deployment
4. **Monitor mempool**: Use tools to detect potential front-running attempts

## Example Project Structure

```
my-project/
├── src/
│   ├── MyContract.sol
│   └── interfaces/
│       └── IMyContract.sol
├── script/
│   ├── DeployProduction.s.sol
│   └── DeployStaging.s.sol
├── deployments/
│   ├── production/
│   │   ├── 1-latest.json
│   │   └── 8453-latest.json
│   └── staging/
│       └── 11155111-latest.json
├── test/
├── lib/
│   └── foundry-deployer/
├── .env
├── .env.example
├── foundry.toml
└── README.md
```
