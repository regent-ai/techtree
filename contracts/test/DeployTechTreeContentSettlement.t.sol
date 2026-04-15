// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { TechTreeContentSettlement } from "../src/TechTreeContentSettlement.sol";
import { DeployTechTreeContentSettlement } from "../script/DeployTechTreeContentSettlement.s.sol";

contract DeployTechTreeContentSettlementHarness is DeployTechTreeContentSettlement {
    function exposedCheckChainId(string memory target) external view {
        _checkChainId(target);
    }

    function exposedPrivateKeyForTarget(string memory target) external returns (uint256) {
        return _privateKeyForTarget(target);
    }
}

contract DeployTechTreeContentSettlementTest is Test {
    DeployTechTreeContentSettlementHarness internal harness;

    function setUp() external {
        harness = new DeployTechTreeContentSettlementHarness();
    }

    function testCheckChainIdAcceptsBaseSepolia() external {
        vm.chainId(84_532);
        harness.exposedCheckChainId("base-sepolia");
    }

    function testCheckChainIdRejectsWrongChainForBaseSepolia() external {
        vm.chainId(31_337);
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployTechTreeContentSettlement.UnexpectedChainId.selector,
                uint256(84_532),
                uint256(31_337)
            )
        );
        harness.exposedCheckChainId("base-sepolia");
    }

    function testCheckChainIdRejectsUnknownTarget() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployTechTreeContentSettlement.InvalidDeployTarget.selector,
                "unsupported-target"
            )
        );
        harness.exposedCheckChainId("unsupported-target");
    }

    function testRunBaseSepoliaDeploysSettlementWithConfiguredAddresses() external {
        vm.chainId(84_532);
        vm.setEnv("BASE_SEPOLIA_PRIVATE_KEY", "12345");
        vm.setEnv(
            "AUTOSKILL_BASE_SEPOLIA_USDC_TOKEN",
            "0x00000000000000000000000000000000000000aa"
        );
        vm.setEnv(
            "AUTOSKILL_BASE_SEPOLIA_TREASURY_ADDRESS",
            "0x00000000000000000000000000000000000000bb"
        );

        TechTreeContentSettlement deployed = harness.runBaseSepolia();

        assertEq(address(deployed.usdcToken()), address(0x00000000000000000000000000000000000000AA));
        assertEq(deployed.treasury(), address(0x00000000000000000000000000000000000000bb));
    }

    function testPrivateKeySelectionUsesTargetSpecificEnv() external {
        vm.setEnv("BASE_SEPOLIA_PRIVATE_KEY", "12345");

        assertEq(harness.exposedPrivateKeyForTarget("base-sepolia"), 12345);
    }
}
