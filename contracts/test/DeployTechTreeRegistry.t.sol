// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { TechTreeRegistry } from "../src/TechTreeRegistry.sol";
import { DeployTechTreeRegistry } from "../script/DeployTechTreeRegistry.s.sol";

contract DeployTechTreeRegistryHarness is DeployTechTreeRegistry {
    function exposedCheckChainId(string memory target) external view {
        _checkChainId(target);
    }

    function exposedPrivateKeyForTarget(string memory target) external returns (uint256) {
        return _privateKeyForTarget(target);
    }
}

contract DeployTechTreeRegistryTest is Test {
    DeployTechTreeRegistryHarness internal harness;

    function setUp() external {
        harness = new DeployTechTreeRegistryHarness();
    }

    function testCheckChainIdAcceptsBaseMainnet() external {
        vm.chainId(8_453);
        harness.exposedCheckChainId("base-mainnet");
    }

    function testCheckChainIdRejectsWrongChainForBaseMainnet() external {
        vm.chainId(31_337);
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployTechTreeRegistry.UnexpectedChainId.selector, uint256(8_453), uint256(31_337)
            )
        );
        harness.exposedCheckChainId("base-mainnet");
    }

    function testCheckChainIdRejectsUnknownTarget() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployTechTreeRegistry.InvalidDeployTarget.selector, "unsupported-target"
            )
        );
        harness.exposedCheckChainId("unsupported-target");
    }

    function testRunBaseMainnetDeploysRegistry() external {
        vm.chainId(8_453);
        vm.setEnv("BASE_MAINNET_PRIVATE_KEY", "12345");

        TechTreeRegistry deployed = harness.runBaseMainnet();

        assertEq(address(deployed) != address(0), true);
        assertEq(deployed.exists(bytes32(uint256(1))), false);
    }

    function testPrivateKeySelectionUsesTargetSpecificEnv() external {
        vm.setEnv("BASE_MAINNET_PRIVATE_KEY", "12345");

        assertEq(harness.exposedPrivateKeyForTarget("base-mainnet"), 12345);
    }
}
