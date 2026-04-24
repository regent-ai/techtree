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

    function testCheckChainIdAcceptsBaseSepolia() external {
        vm.chainId(84_532);
        harness.exposedCheckChainId("base-sepolia");
    }

    function testCheckChainIdRejectsWrongChainForBaseSepolia() external {
        vm.chainId(31_337);
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployTechTreeRegistry.UnexpectedChainId.selector, uint256(84_532), uint256(31_337)
            )
        );
        harness.exposedCheckChainId("base-sepolia");
    }

    function testCheckChainIdRejectsUnknownTarget() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployTechTreeRegistry.InvalidDeployTarget.selector, "unsupported-target"
            )
        );
        harness.exposedCheckChainId("unsupported-target");
    }

    function testRunBaseSepoliaDeploysRegistry() external {
        vm.chainId(84_532);
        vm.setEnv("BASE_SEPOLIA_PRIVATE_KEY", "12345");

        TechTreeRegistry deployed = harness.runBaseSepolia();

        assertEq(address(deployed) != address(0), true);
        assertEq(deployed.exists(bytes32(uint256(1))), false);
    }

    function testPrivateKeySelectionUsesTargetSpecificEnv() external {
        vm.setEnv("BASE_SEPOLIA_PRIVATE_KEY", "12345");

        assertEq(harness.exposedPrivateKeyForTarget("base-sepolia"), 12345);
    }
}
