// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";

import { DeployTechStack } from "../script/DeployTechStack.s.sol";

contract DeployTechStackHarness is DeployTechStack {
    function exposedCheckChainId(string memory target) external view {
        _checkChainId(target);
    }

    function exposedPrivateKeyForTarget(string memory target) external view returns (uint256) {
        return _privateKeyForTarget(target);
    }
}

contract DeployTechStackTest is Test {
    address internal constant ADMIN = address(0xA11CE);
    address internal constant OWNER = address(0x0A0A);
    address internal constant ROOT_MANAGER = address(0xBEEF);
    address internal constant LEADERBOARD_MANAGER = address(0xC0DE);
    address internal constant PAUSER = address(0xD00D);
    uint256 internal constant DEPLOYER_KEY = 12_345;

    DeployTechStackHarness internal harness;

    function setUp() external {
        harness = new DeployTechStackHarness();
    }

    function testCheckChainIdAcceptsBaseSepoliaAndMainnet() external {
        vm.chainId(84_532);
        harness.exposedCheckChainId("base-sepolia");

        vm.chainId(8_453);
        harness.exposedCheckChainId("base-mainnet");
    }

    function testCheckChainIdRejectsWrongChainForBaseSepolia() external {
        vm.chainId(8_453);
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployTechStack.UnexpectedChainId.selector, uint256(84_532), uint256(8_453)
            )
        );
        harness.exposedCheckChainId("base-sepolia");
    }

    function testRunAnvilDeploysAndWiresStack() external {
        vm.chainId(31_337);
        _setEnv();

        DeployTechStack.DeployedContracts memory deployed = harness.runAnvil();
        address deployer = vm.addr(DEPLOYER_KEY);

        assertEq(address(deployed.tech) != address(0), true);
        assertEq(deployed.tech.maxSupply(), 1_000_000 ether);
        assertEq(
            deployed.tech.hasRole(deployed.tech.MINTER_ROLE(), address(deployed.controller)), true
        );
        assertEq(deployed.tech.hasRole(deployed.tech.MINTER_ROLE(), ADMIN), false);
        assertEq(deployed.tech.hasRole(deployed.tech.DEFAULT_ADMIN_ROLE(), ADMIN), true);
        assertEq(deployed.tech.hasRole(deployed.tech.DEFAULT_ADMIN_ROLE(), deployer), false);

        assertEq(address(deployed.vault.TECH()), address(deployed.tech));
        assertEq(address(deployed.vault.exitSwap()), address(deployed.exitSwap));
        assertEq(deployed.exitSwap.vault(), address(deployed.vault));
        assertEq(deployed.exitSwap.owner(), OWNER);
        assertEq(deployed.vault.votingActivated(), true);
        assertEq(
            deployed.vault.hasRole(deployed.vault.REWARD_CREDITOR_ROLE(), address(deployed.router)),
            true
        );
        assertEq(deployed.vault.hasRole(deployed.vault.PAUSER_ROLE(), PAUSER), true);

        assertEq(address(deployed.router.TECH()), address(deployed.tech));
        assertEq(address(deployed.router.vault()), address(deployed.vault));
        assertEq(
            deployed.router
                .hasRole(deployed.router.EMISSION_CONTROLLER_ROLE(), address(deployed.controller)),
            true
        );
        assertEq(deployed.router.hasRole(deployed.router.ROOT_MANAGER_ROLE(), ROOT_MANAGER), true);

        assertEq(address(deployed.controller.TECH()), address(deployed.tech));
        assertEq(address(deployed.controller.rewardRouter()), address(deployed.router));
        assertEq(address(deployed.controller.scienceShareSource()), address(deployed.vault));
        assertEq(deployed.controller.owner(), OWNER);

        assertEq(
            deployed.leaderboardRegistry
                .hasRole(
                    deployed.leaderboardRegistry.LEADERBOARD_MANAGER_ROLE(), LEADERBOARD_MANAGER
                ),
            true
        );
        assertEq(
            deployed.leaderboardRegistry
                .hasRole(deployed.leaderboardRegistry.GOVERNANCE_ROLE(), OWNER),
            true
        );
    }

    function testPrivateKeySelectionUsesTargetSpecificEnv() external {
        vm.setEnv("BASE_SEPOLIA_PRIVATE_KEY", "98765");

        assertEq(harness.exposedPrivateKeyForTarget("base-sepolia"), 98_765);
    }

    function _setEnv() internal {
        vm.setEnv("ANVIL_PRIVATE_KEY", vm.toString(DEPLOYER_KEY));
        _setAddressEnv("TECH_ADMIN_ADDRESS", ADMIN);
        _setAddressEnv("TECH_OWNER_ADDRESS", OWNER);
        _setAddressEnv("TECH_ROOT_MANAGER_ADDRESS", ROOT_MANAGER);
        _setAddressEnv("TECH_LEADERBOARD_MANAGER_ADDRESS", LEADERBOARD_MANAGER);
        _setAddressEnv("TECH_PAUSER_ADDRESS", PAUSER);
        _setAddressEnv("TECH_AGENT_REGISTRY_ADDRESS", address(0x1001));
        _setAddressEnv("TECH_WETH_TOKEN", address(0x2002));
        _setAddressEnv("TECH_REGENT_TOKEN", address(0x3003));
        _setAddressEnv("TECH_UNISWAP_V4_POOL_MANAGER", address(0x4004));
        _setAddressEnv("TECH_UNIVERSAL_ROUTER", address(0x5005));
        _setAddressEnv("TECH_PERMIT2", address(0x6006));
        _setAddressEnv("TECH_ETH_USD_FEED", address(0x7007));
        _setAddressEnv("TECH_BASE_SEQUENCER_UPTIME_FEED", address(0x8008));
        vm.setEnv("TECH_MAX_SUPPLY", vm.toString(uint256(1_000_000 ether)));
        vm.setEnv("TECH_EPOCH_DURATION_SECONDS", "86400");
        vm.setEnv("TECH_MAX_EPOCHS", "2600");
        vm.setEnv("TECH_INITIAL_EPOCH_EMISSION", vm.toString(uint256(1_000 ether)));
        vm.setEnv("TECH_MAX_EMISSION_SUPPLY", vm.toString(uint256(500_000 ether)));
        vm.setEnv("TECH_DECAY_NUMERATOR", "999");
        vm.setEnv("TECH_DECAY_DENOMINATOR", "1000");
        vm.setEnv("TECH_WETH_POOL_FEE", "3000");
        vm.setEnv("TECH_WETH_POOL_TICK_SPACING", "60");
        _setAddressEnv("TECH_WETH_POOL_HOOKS", address(0));
        vm.setEnv("WETH_REGENT_POOL_FEE", "3000");
        vm.setEnv("WETH_REGENT_POOL_TICK_SPACING", "60");
        _setAddressEnv("WETH_REGENT_POOL_HOOKS", address(0));
        vm.setEnv("TECH_WETH_MIN_LIQUIDITY", "1");
        vm.setEnv("WETH_REGENT_MIN_LIQUIDITY", "1");
        vm.setEnv("TECH_ETH_USD_MAX_STALENESS_SECONDS", "3600");
        vm.setEnv("TECH_SEQUENCER_GRACE_PERIOD_SECONDS", "3600");
    }

    function _setAddressEnv(string memory key, address value) internal {
        vm.setEnv(key, vm.toString(value));
    }
}
