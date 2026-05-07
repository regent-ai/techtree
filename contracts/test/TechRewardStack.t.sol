// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";

import { TechAgentRewardVault } from "../src/TechAgentRewardVault.sol";
import { TechEmissionControllerV2 } from "../src/TechEmissionControllerV2.sol";
import { TechRewardRouter } from "../src/TechRewardRouter.sol";
import { TechToken } from "../src/TechToken.sol";
import { MockAgentRegistry } from "./mocks/MockAgentRegistry.sol";
import { MockExitFeeSplitter } from "./mocks/MockExitFeeSplitter.sol";

contract TechRewardStackTest is Test {
    address internal constant ADMIN = address(0xA11CE);
    address internal constant ALICE = address(0xA11CE1);
    address internal constant BOB = address(0xB0B);
    uint64 internal constant EPOCH_DURATION = 1 days;
    bytes32 internal constant ALLOCATION_REF = keccak256("allocation");

    TechToken internal tech;
    MockAgentRegistry internal registry;
    MockExitFeeSplitter internal exitFeeSplitter;
    TechAgentRewardVault internal vault;
    TechRewardRouter internal router;
    TechEmissionControllerV2 internal controller;

    function setUp() public {
        tech = new TechToken(ADMIN, 1_000 ether);
        registry = new MockAgentRegistry();
        registry.setOwner(1, ALICE);
        registry.setOwner(2, BOB);
        exitFeeSplitter = new MockExitFeeSplitter();
        vault = new TechAgentRewardVault(
            address(tech), address(registry), address(exitFeeSplitter), ADMIN
        );
        router = new TechRewardRouter(address(tech), address(vault), ADMIN);
        controller = new TechEmissionControllerV2(
            address(tech),
            address(vault),
            address(router),
            EPOCH_DURATION,
            2_600,
            100 ether,
            500 ether,
            999,
            1_000,
            ADMIN
        );

        vm.startPrank(ADMIN);
        tech.grantRole(tech.MINTER_ROLE(), address(controller));
        tech.revokeRole(tech.MINTER_ROLE(), ADMIN);
        router.grantRole(router.EMISSION_CONTROLLER_ROLE(), address(controller));
        router.grantRole(router.ROOT_MANAGER_ROLE(), ADMIN);
        vault.grantRole(vault.REWARD_CREDITOR_ROLE(), address(router));
        vault.activateVoting();
        vm.stopPrank();
    }

    function testRollEpochMintsBudgetToRouterWithSmoothDecay() public {
        vm.warp(block.timestamp + EPOCH_DURATION);
        controller.rollEpoch();

        (
            uint256 totalEmission,
            uint256 scienceBudget,
            uint256 inputBudget,
            uint256 scienceAllocated,
            uint256 inputAllocated,
            bool exists
        ) = router.epochBudgets(0);

        assertTrue(exists);
        assertEq(totalEmission, 100 ether);
        assertEq(scienceBudget, 100 ether);
        assertEq(inputBudget, 0);
        assertEq(scienceAllocated, 0);
        assertEq(inputAllocated, 0);
        assertEq(tech.balanceOf(address(router)), 100 ether);
        assertLt(controller.currentEpochEmission(), 100 ether);
    }

    function testClaimCreditsLockedTechToAgent() public {
        _rollFirstEpoch();

        uint256 amount = 10 ether;
        bytes32 leaf = router.allocationLeaf(
            0, TechRewardRouter.RewardLane.Science, 1, amount, ALLOCATION_REF
        );

        vm.prank(ADMIN);
        router.postAllocationRoot(
            0, TechRewardRouter.RewardLane.Science, leaf, amount, keccak256("manifest"), 0
        );

        router.claim(
            0, TechRewardRouter.RewardLane.Science, 1, amount, ALLOCATION_REF, new bytes32[](0)
        );

        assertEq(vault.lockedBalance(1), amount);
        assertEq(vault.totalLockedTech(), amount);
        assertEq(tech.balanceOf(address(vault)), amount);
    }

    function testDoubleClaimReverts() public {
        _postAndClaim(1, 10 ether);

        vm.expectRevert(TechRewardRouter.AlreadyClaimed.selector);
        router.claim(
            0, TechRewardRouter.RewardLane.Science, 1, 10 ether, ALLOCATION_REF, new bytes32[](0)
        );
    }

    function testAgentOwnerCanSetPreferenceAndWithdraw() public {
        _postAndClaim(1, 100 ether);

        vm.prank(ALICE);
        vault.setSciencePreference(1, 0);
        assertEq(vault.sciencePreferenceWad(1), 0);
        assertEq(vault.currentScienceShareWad(), 0);

        vm.prank(ALICE);
        vault.withdraw(1, 100 ether, ALICE, 1 ether, block.timestamp + 1);

        assertEq(vault.lockedBalance(1), 0);
        assertEq(tech.balanceOf(ALICE), 90 ether);
        assertEq(tech.balanceOf(address(exitFeeSplitter)), 10 ether);
        assertEq(exitFeeSplitter.lastTechAmount(), 10 ether);
        assertEq(exitFeeSplitter.lastMinUsdcOut(), 1 ether);
        assertEq(exitFeeSplitter.lastSourceRef() != bytes32(0), true);
    }

    function testOwnershipTransferChangesWithdrawalAuthority() public {
        _postAndClaim(1, 10 ether);
        registry.setOwner(1, BOB);

        vm.prank(ALICE);
        vm.expectRevert(TechAgentRewardVault.OnlyAgentOwner.selector);
        vault.withdraw(1, 10 ether, ALICE, 1 ether, block.timestamp + 1);

        vm.prank(BOB);
        vault.withdraw(1, 10 ether, BOB, 1 ether, block.timestamp + 1);
        assertEq(tech.balanceOf(BOB), 9 ether);
    }

    function testSwapFailureRevertsWithoutLosingLockedBalance() public {
        _postAndClaim(1, 100 ether);
        exitFeeSplitter.setShouldRevert(true);

        vm.prank(ALICE);
        vm.expectRevert(bytes("SPLITTER_FAILED"));
        vault.withdraw(1, 100 ether, ALICE, 1 ether, block.timestamp + 1);

        assertEq(vault.lockedBalance(1), 100 ether);
        assertEq(tech.balanceOf(address(vault)), 100 ether);
    }

    function testInputBudgetAppearsWhenScienceShareBelowFull() public {
        _postAndClaim(1, 100 ether);
        vm.prank(ALICE);
        vault.setSciencePreference(1, 0);

        vm.warp(block.timestamp + EPOCH_DURATION);
        controller.rollEpoch();

        vm.warp(block.timestamp + EPOCH_DURATION);
        controller.rollEpoch();

        (, uint256 scienceBudget, uint256 inputBudget,,,) = router.epochBudgets(2);
        assertEq(scienceBudget, 0);
        assertGt(inputBudget, 0);
    }

    function _rollFirstEpoch() internal {
        vm.warp(block.timestamp + EPOCH_DURATION);
        controller.rollEpoch();
    }

    function _postAndClaim(uint256 agentId, uint256 amount) internal {
        _rollFirstEpoch();
        bytes32 leaf = router.allocationLeaf(
            0, TechRewardRouter.RewardLane.Science, agentId, amount, ALLOCATION_REF
        );

        vm.prank(ADMIN);
        router.postAllocationRoot(
            0, TechRewardRouter.RewardLane.Science, leaf, amount, keccak256("manifest"), 0
        );

        router.claim(
            0,
            TechRewardRouter.RewardLane.Science,
            agentId,
            amount,
            ALLOCATION_REF,
            new bytes32[](0)
        );
    }
}
