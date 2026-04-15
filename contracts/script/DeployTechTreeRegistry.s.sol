// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { TechTreeRegistry } from "../src/TechTreeRegistry.sol";

interface Vm {
    function envOr(string calldata key, string calldata defaultValue)
        external
        returns (string memory);
    function envUint(string calldata key) external returns (uint256);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

/// @notice Deploys TechTreeRegistry with env-based config.
///         DEPLOY_TARGET: anvil | base-sepolia | base-mainnet (default: base-sepolia)
///         ANVIL_PRIVATE_KEY / BASE_SEPOLIA_PRIVATE_KEY / BASE_MAINNET_PRIVATE_KEY required per target.
contract DeployTechTreeRegistry {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    bytes32 internal constant ANVIL_TARGET_HASH = keccak256(bytes("anvil"));
    bytes32 internal constant BASE_SEPOLIA_TARGET_HASH = keccak256(bytes("base-sepolia"));
    bytes32 internal constant BASE_MAINNET_TARGET_HASH = keccak256(bytes("base-mainnet"));
    uint256 internal constant ANVIL_CHAIN_ID = 31_337;
    uint256 internal constant BASE_SEPOLIA_CHAIN_ID = 84_532;
    uint256 internal constant BASE_MAINNET_CHAIN_ID = 8_453;

    error InvalidDeployTarget(string target);
    error UnexpectedChainId(uint256 expected, uint256 actual);

    function run() external returns (TechTreeRegistry deployed) {
        string memory target = vm.envOr("DEPLOY_TARGET", string("base-sepolia"));
        deployed = _runTarget(target);
    }

    function runAnvil() external returns (TechTreeRegistry deployed) {
        deployed = _runTarget("anvil");
    }

    function runBaseSepolia() external returns (TechTreeRegistry deployed) {
        deployed = _runTarget("base-sepolia");
    }

    function runBaseMainnet() external returns (TechTreeRegistry deployed) {
        deployed = _runTarget("base-mainnet");
    }

    function _runTarget(string memory target) internal returns (TechTreeRegistry deployed) {
        _checkChainId(target);

        uint256 deployerKey = _privateKeyForTarget(target);

        vm.startBroadcast(deployerKey);
        deployed = new TechTreeRegistry();
        vm.stopBroadcast();
    }

    function _privateKeyForTarget(string memory target) internal returns (uint256) {
        bytes32 targetHash = keccak256(bytes(target));

        if (targetHash == ANVIL_TARGET_HASH) {
            return vm.envUint("ANVIL_PRIVATE_KEY");
        }

        if (targetHash == BASE_SEPOLIA_TARGET_HASH) {
            return vm.envUint("BASE_SEPOLIA_PRIVATE_KEY");
        }

        if (targetHash == BASE_MAINNET_TARGET_HASH) {
            return vm.envUint("BASE_MAINNET_PRIVATE_KEY");
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

        if (targetHash == BASE_SEPOLIA_TARGET_HASH) {
            if (block.chainid != BASE_SEPOLIA_CHAIN_ID) {
                revert UnexpectedChainId(BASE_SEPOLIA_CHAIN_ID, block.chainid);
            }
            return;
        }

        if (targetHash == BASE_MAINNET_TARGET_HASH) {
            if (block.chainid != BASE_MAINNET_CHAIN_ID) {
                revert UnexpectedChainId(BASE_MAINNET_CHAIN_ID, block.chainid);
            }
            return;
        }

        revert InvalidDeployTarget(target);
    }
}
