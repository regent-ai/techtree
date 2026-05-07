// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Script, console2 } from "forge-std/Script.sol";

import { TechAgentRewardVault } from "../src/TechAgentRewardVault.sol";
import { TechEmissionControllerV2 } from "../src/TechEmissionControllerV2.sol";
import { TechExitFeeUsdcSplitter } from "../src/TechExitFeeUsdcSplitter.sol";
import { TechLeaderboardRegistry } from "../src/TechLeaderboardRegistry.sol";
import { TechRewardRouter } from "../src/TechRewardRouter.sol";
import { TechToken } from "../src/TechToken.sol";

/// @notice Verifies deployed TECH v0.2 wiring after a Foundry deploy.
contract VerifyTechStack is Script {
    error MissingCode(string key, address account);
    error AddressMismatch(string key, address expected, address actual);
    error RoleMissing(string key, address account);
    error MinterRoleStillHeld(address account);

    function run() external view {
        TechToken tech = TechToken(_contractAddress("TECH_TOKEN_ADDRESS"));
        TechExitFeeUsdcSplitter exitFeeSplitter =
            TechExitFeeUsdcSplitter(_contractAddress("TECH_EXIT_FEE_SPLITTER_ADDRESS"));
        TechAgentRewardVault vault =
            TechAgentRewardVault(_contractAddress("TECH_AGENT_REWARD_VAULT_ADDRESS"));
        TechRewardRouter router = TechRewardRouter(_contractAddress("TECH_REWARD_ROUTER_ADDRESS"));
        TechEmissionControllerV2 controller =
            TechEmissionControllerV2(_contractAddress("TECH_EMISSION_CONTROLLER_ADDRESS"));
        TechLeaderboardRegistry leaderboards =
            TechLeaderboardRegistry(_contractAddress("TECH_LEADERBOARD_REGISTRY_ADDRESS"));

        address admin = vm.envAddress("TECH_ADMIN_ADDRESS");
        address owner = vm.envAddress("TECH_OWNER_ADDRESS");
        address agentRegistry = vm.envAddress("TECH_AGENT_REGISTRY_ADDRESS");
        address usdc = vm.envAddress("TECH_USDC_TOKEN");
        address regentRevenueStaking = vm.envAddress("TECH_REGENT_REVENUE_STAKING");
        address rootManager = vm.envAddress("TECH_ROOT_MANAGER_ADDRESS");
        address leaderboardManager = vm.envAddress("TECH_LEADERBOARD_MANAGER_ADDRESS");
        address pauser = vm.envAddress("TECH_PAUSER_ADDRESS");

        _assertAddress("vault.TECH", address(tech), address(vault.TECH()));
        _assertAddress("vault.agentRegistry", agentRegistry, address(vault.agentRegistry()));
        _assertAddress(
            "vault.exitFeeSplitter", address(exitFeeSplitter), address(vault.exitFeeSplitter())
        );
        _assertAddress("exitFeeSplitter.vault", address(vault), exitFeeSplitter.vault());
        _assertAddress("exitFeeSplitter.owner", owner, exitFeeSplitter.owner());
        _assertAddress("exitFeeSplitter.USDC", usdc, address(exitFeeSplitter.USDC()));
        _assertAddress(
            "exitFeeSplitter.regentRevenueStaking",
            regentRevenueStaking,
            address(exitFeeSplitter.regentRevenueStaking())
        );
        _assertAddress("router.TECH", address(tech), address(router.TECH()));
        _assertAddress("router.vault", address(vault), address(router.vault()));
        _assertAddress("controller.TECH", address(tech), address(controller.TECH()));
        _assertAddress(
            "controller.scienceShareSource",
            address(vault),
            address(controller.scienceShareSource())
        );
        _assertAddress(
            "controller.rewardRouter", address(router), address(controller.rewardRouter())
        );
        _assertAddress("controller.owner", owner, controller.owner());

        _requireRole("tech.admin", tech.hasRole(tech.DEFAULT_ADMIN_ROLE(), admin), admin);
        _requireRole(
            "tech.controllerMinter",
            tech.hasRole(tech.MINTER_ROLE(), address(controller)),
            address(controller)
        );
        if (tech.hasRole(tech.MINTER_ROLE(), admin)) revert MinterRoleStillHeld(admin);

        _requireRole(
            "vault.routerCreditor",
            vault.hasRole(vault.REWARD_CREDITOR_ROLE(), address(router)),
            address(router)
        );
        _requireRole("vault.pauser", vault.hasRole(vault.PAUSER_ROLE(), pauser), pauser);
        _requireRole("vault.admin", vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), admin), admin);
        _requireRole(
            "router.controller",
            router.hasRole(router.EMISSION_CONTROLLER_ROLE(), address(controller)),
            address(controller)
        );
        _requireRole(
            "router.rootManager",
            router.hasRole(router.ROOT_MANAGER_ROLE(), rootManager),
            rootManager
        );
        _requireRole("router.pauser", router.hasRole(router.PAUSER_ROLE(), pauser), pauser);
        _requireRole("router.admin", router.hasRole(router.DEFAULT_ADMIN_ROLE(), admin), admin);
        _requireRole(
            "leaderboards.manager",
            leaderboards.hasRole(leaderboards.LEADERBOARD_MANAGER_ROLE(), leaderboardManager),
            leaderboardManager
        );
        _requireRole(
            "leaderboards.governance",
            leaderboards.hasRole(leaderboards.GOVERNANCE_ROLE(), owner),
            owner
        );
        _requireRole(
            "leaderboards.admin",
            leaderboards.hasRole(leaderboards.DEFAULT_ADMIN_ROLE(), admin),
            admin
        );

        console2.log("TECH_STACK_VERIFY_JSON:{\"ok\":true}");
    }

    function _contractAddress(string memory key) internal view returns (address account) {
        account = vm.envAddress(key);
        if (account.code.length == 0) revert MissingCode(key, account);
    }

    function _assertAddress(string memory key, address expected, address actual) internal pure {
        if (expected != actual) revert AddressMismatch(key, expected, actual);
    }

    function _requireRole(string memory key, bool ok, address account) internal pure {
        if (!ok) revert RoleMissing(key, account);
    }
}
