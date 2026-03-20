// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { TechTreeRegistry } from "../src/TechTreeRegistry.sol";

interface Vm {
    function envOr(string calldata key, string calldata defaultValue)
        external
        returns (string memory);
    function envOr(string calldata key, address defaultValue) external returns (address);
    function envUint(string calldata key) external returns (uint256);
    function addr(uint256 privateKey) external returns (address);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

/// @notice Deploys TechTreeRegistry with env-based config.
///         DEPLOY_TARGET: anvil | sepolia | mainnet (default: anvil)
///         ANVIL_PRIVATE_KEY / ETHEREUM_SEPOLIA_PRIVATE_KEY / ETHEREUM_MAINNET_PRIVATE_KEY required per target.
///         REGISTRY_ADMIN and REGISTRY_INITIAL_WRITER are optional.
contract DeployTechTreeRegistry {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    bytes32 internal constant ANVIL_TARGET_HASH = keccak256(bytes("anvil"));
    bytes32 internal constant SEPOLIA_TARGET_HASH = keccak256(bytes("sepolia"));
    bytes32 internal constant MAINNET_TARGET_HASH = keccak256(bytes("mainnet"));
    uint256 internal constant ANVIL_CHAIN_ID = 31_337;
    uint256 internal constant SEPOLIA_CHAIN_ID = 11_155_111;
    uint256 internal constant MAINNET_CHAIN_ID = 1;

    error InvalidDeployTarget(string target);
    error UnexpectedChainId(uint256 expected, uint256 actual);

    function run() external returns (TechTreeRegistry deployed) {
        string memory target = vm.envOr("DEPLOY_TARGET", string("anvil"));
        deployed = _runTarget(target);
    }

    function runAnvil() external returns (TechTreeRegistry deployed) {
        deployed = _runTarget("anvil");
    }

    function runSepolia() external returns (TechTreeRegistry deployed) {
        deployed = _runTarget("sepolia");
    }

    function runMainnet() external returns (TechTreeRegistry deployed) {
        deployed = _runTarget("mainnet");
    }

    function _runTarget(string memory target) internal returns (TechTreeRegistry deployed) {
        _checkChainId(target);

        uint256 deployerKey = _privateKeyForTarget(target);
        address deployer = vm.addr(deployerKey);
        address admin = vm.envOr("REGISTRY_ADMIN", deployer);
        address initialWriter = vm.envOr("REGISTRY_INITIAL_WRITER", deployer);

        vm.startBroadcast(deployerKey);
        deployed = new TechTreeRegistry(admin, initialWriter);
        vm.stopBroadcast();
    }

    function _privateKeyForTarget(string memory target) internal returns (uint256) {
        bytes32 targetHash = keccak256(bytes(target));

        if (targetHash == ANVIL_TARGET_HASH) {
            return vm.envUint("ANVIL_PRIVATE_KEY");
        }

        if (targetHash == SEPOLIA_TARGET_HASH) {
            return vm.envUint("ETHEREUM_SEPOLIA_PRIVATE_KEY");
        }

        if (targetHash == MAINNET_TARGET_HASH) {
            return vm.envUint("ETHEREUM_MAINNET_PRIVATE_KEY");
        }

        revert InvalidDeployTarget(target);
    }

    function _checkChainId(string memory target) internal view {
        bytes32 targetHash = keccak256(bytes(target));

        if (targetHash == ANVIL_TARGET_HASH) {
            if (block.chainid != ANVIL_CHAIN_ID) {
                revert UnexpectedChainId(ANVIL_CHAIN_ID, block.chainid);
            }
            return;
        }

        if (targetHash == SEPOLIA_TARGET_HASH) {
            if (block.chainid != SEPOLIA_CHAIN_ID) {
                revert UnexpectedChainId(SEPOLIA_CHAIN_ID, block.chainid);
            }
            return;
        }

        if (targetHash == MAINNET_TARGET_HASH) {
            if (block.chainid != MAINNET_CHAIN_ID) {
                revert UnexpectedChainId(MAINNET_CHAIN_ID, block.chainid);
            }
            return;
        }

        revert InvalidDeployTarget(target);
    }
}
