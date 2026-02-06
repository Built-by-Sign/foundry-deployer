# Foundry Deployer

**A Foundry package for deterministic CREATE3 deployments with version management, JSON tracking, and GitHub Actions integration.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg)](https://getfoundry.sh/)

---

## Features

- **CREATE3 Deployments**: Deterministic contract addresses across chains using CreateX
- **Version Management**: Built-in EVM version suffix support (cancun, shanghai, paris, etc.)
- **JSON Tracking**: Automatic deployment artifact tracking with version-to-address mappings
- **GitHub Actions**: Reusable workflow for automated deployments
- **Ownership Management**: Automatic ownership transfer on mainnet chains
- **Extensible**: Virtual methods and hooks for custom deployment logic

## Quick Start

### Installation

```bash
forge install EthSign/foundry-deployer
```

### Basic Usage

1. **Create a versioned contract:**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Versionable} from "foundry-deployer/Versionable.sol";
import {Ownable} from "solady/auth/Ownable.sol";

contract MyContract is Versionable, Ownable {
    constructor(string memory evmSuffix_, address owner_) Versionable(evmSuffix_) {
        _initializeOwner(owner_);
    }

    function _baseVersion() internal pure override returns (string memory) {
        return "1.0.0-MyContract";
    }
}
```

2. **Create a deployment script:**

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DeployHelper} from "foundry-deployer/DeployHelper.sol";

contract DeployMyContract is DeployHelper {
    function setUp() public override {
        // Use explicit deployer address that matches broadcast sender
        _setUp("production", msg.sender);
    }

    function run() public {
        vm.startBroadcast();

        // EVM suffix is auto-detected from foundry.toml
        // Owner is set in constructor — no atomic init needed
        bytes memory creationCode = abi.encodePacked(
            type(MyContract).creationCode,
            abi.encode(_getEvmSuffix(), msg.sender)
        );

        address deployed = deploy(creationCode);
        _checkChainAndSetOwner(deployed);

        vm.stopBroadcast();
        _afterAll();
    }
}
```

3. **Configure environment variables:**

```bash
# .env
PROD_OWNER=0x... # Production owner address
MAINNET_CHAIN_IDS=1,56,137,8453 # Comma-separated mainnet chain IDs
ALLOWED_DEPLOYMENT_SENDER=0x... # Address allowed to save deployments
```

### Environment Variables

| Variable                    | Description                                                                                                       |
| --------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `PROD_OWNER`                | Production owner address for mainnet deployments (required)                                                       |
| `MAINNET_CHAIN_IDS`         | Comma-separated list of mainnet chain IDs (required)                                                              |
| `ALLOWED_DEPLOYMENT_SENDER` | Address allowed to save deployment artifacts (required)                                                           |
| `LOCAL_CHAIN_ID`            | Override the default local chain ID (31337) for CreateX auto-etching. Set to `1337` for Hardhat. Default: `31337` |
| `ALLOW_CREATEX_ETCH`        | Set to `true` to enable CreateX etching on any chain (e.g., fork simulations). Default: `false`                   |
| `FORCE_DEPLOY`              | Set to `true` to allow deployments with differing verification inputs. Default: `false`                           |
| `SKIP_STANDARD_JSON_INPUT`  | Set to `true` to skip verification input generation/checks. Default: `false`                                      |

4. **Configure EVM version (optional):**

```toml
# foundry.toml
[profile.default]
evm_version = "cancun"  # Auto-detected and appended to version strings
```

5. **Deploy:**

```bash
forge script script/DeployMyContract.s.sol --rpc-url $RPC_URL --broadcast
```

The EVM suffix is automatically detected from `foundry.toml` using the active `FOUNDRY_PROFILE` (falling back to `profile.default`, then root-level `evm_version`) and appended to version strings (e.g., "1.0.0-MyContract-cancun").

## Documentation

- [Getting Started Guide](./docs/GETTING_STARTED.md)
- [API Reference](./docs/API_REFERENCE.md)

## How It Works

### CREATE3 Deterministic Deployment

Foundry Deployer uses CREATE3 via [CreateX](https://github.com/pcaversaccio/createx) to deploy contracts at deterministic addresses:

- **Same address across chains**: Deploy to the same address on different networks
- **Collision-free**: Each version gets a unique address
- **No nonce dependency**: Deploy in any order without address conflicts

### Version Management

Contracts implement `IVersionable` and use the `Version` library for EVM-specific versioning:

```
Base version: "1.0.0-MyContract"
With EVM suffix: "1.0.0-MyContract-cancun"
With custom suffix: "1.0.0-MyContract-cancun-beta"
```

### Atomic Deploy+Init

For contracts that use post-deploy initialization (e.g., `initializeOwner(address)` instead of constructor-based ownership), there is a front-running risk: an attacker could call `initializeOwner()` between deployment and your initialization transaction.

Foundry Deployer supports **atomic deploy+init** via CreateX's `deployCreate3AndInit`, which deploys and initializes in a single transaction. To enable it, override `_getPostDeployInitData()`:

```solidity
contract MyDeploy is DeployHelper {
    function _getPostDeployInitData() internal virtual override returns (bytes memory) {
        return abi.encodeWithSignature("initializeOwner(address)", _deployer);
    }
}
```

**Default behavior:** Plain `deployCreate3` with no post-deploy init call. This is safe for contracts that set their owner in the constructor. Override `_getPostDeployInitData()` to return non-empty calldata when you need atomic initialization.

See [`script/examples/AtomicDeployment.s.sol`](./script/examples/AtomicDeployment.s.sol) for a complete example.

### Deployment Tracking

All deployments are automatically tracked in JSON files:

```
deployments/
  production/
    1-latest.json           # Latest deployments on Ethereum
    8453-latest.json        # Latest deployments on Base
    standard-json-inputs/   # Verification data
      1.0.0-MyContract-cancun.json
```

## GitHub Actions Integration

Create a reusable workflow in your repository:

```yaml
# .github/workflows/deploy-base.yml
name: Deploy to Base

on:
  workflow_dispatch:

jobs:
  deploy:
    uses: EthSign/foundry-deployer/.github/workflows/deploy.yml@main
    with:
      network_name: Base
      chain_id: "8453"
      deploy_script: script/DeployMyContract.s.sol
      deployment_category: production
      evm_version: cancun
    secrets:
      rpc_url: ${{ secrets.BASE_RPC_URL }}
      deployment_private_key: ${{ secrets.DEPLOYER_KEY }}
```

## Examples

See the [examples directory](./script/examples/) for complete examples:

- **[SimpleDeployment.s.sol](./script/examples/SimpleDeployment.s.sol)** - Basic single-contract deployment (constructor-based ownership)
- **[MultiContract.s.sol](./script/examples/MultiContract.s.sol)** - Multi-contract deployment with atomic init and cross-references
- **[AtomicDeployment.s.sol](./script/examples/AtomicDeployment.s.sol)** - Atomic deploy+init for front-running prevention

## Advanced Features

### Custom Deployment Logic

Override virtual methods to customize behavior:

```solidity
contract CustomDeploy is DeployHelper {
    function _getSalt(string memory version) internal view override returns (bytes32) {
        // Custom salt generation logic
        return keccak256(abi.encodePacked(version, block.chainid));
    }

    function _checkChainAndSetOwner(address instance) internal override {
        // Custom ownership logic
        if (block.chainid == 1) {
            vm.broadcast();
            Ownable(instance).transferOwnership(MAINNET_OWNER);
        }
    }
}
```

## Known Limitations

- **Hardware wallets not supported**: The `__getNameVersionAndVariant()` function pauses and resumes broadcasts using `vm.broadcast(address)`, which requires access to a private key. Hardware wallet deployments (Ledger/Trezor) will fail because Foundry cannot programmatically re-initiate the broadcast with a hardware signer.

## Testing

The project includes comprehensive test coverage with 100+ tests:

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Generate coverage report
forge coverage

# Run specific test file
forge test --match-path test/DeployHelper.t.sol
```

## Dependencies

- [forge-std](https://github.com/foundry-rs/forge-std) - Foundry standard library
- [CreateX](https://github.com/pcaversaccio/createx) - CREATE3 factory (embedded bytecode)
- [solady](https://github.com/Vectorized/solady) - Gas-optimized Solidity utilities

## License

This project is licensed under [MIT](./LICENSE). The bundled `src/helpers/strings.sol` library is licensed under [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0).

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Credits

Built by [EthSign](https://github.com/EthSign) for the Foundry ecosystem.

Based on deployment infrastructure from [TokenTable](https://tokentable.xyz).
