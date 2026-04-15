// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { TechEmissionController } from "../../src/TechEmissionController.sol";
import { TechContractsBase } from "../utils/TechContractsBase.sol";

contract TechEmissionControllerTest is TechContractsBase {
    uint64 internal constant EPOCH_DURATION = 10 hours;
    uint64 internal constant HALVING_INTERVAL = 2;

    function setUp() public {
        _deployVotingStack();
        _deployController(EPOCH_DURATION, HALVING_INTERVAL, 9 ether);

        _fundAndApprove(ALICE, 1_000 ether);
    }

    function test_rollEpochRevertsBeforeEpochEnd() public {
        vm.expectRevert(bytes("epoch active"));
        controller.rollEpoch();
    }

    function test_rollEpochOpenToAnyCaller() public {
        _grantControllerMinterRole();
        _activateVoting();
        _setPreference(ALICE, WAD / 2);
        _deposit(ALICE, 100 ether);

        _warpToEpochEnd(0);
        vm.prank(RANDOM_CALLER);
        controller.rollEpoch();

        assertEq(tech.balanceOf(SCIENCE_DISTRIBUTOR), 9 ether);
        assertEq(controller.currentEpoch(), 1);
        assertEq(controller.currentScienceShareWad(), WAD / 2);
    }

    function test_rollEpochPaysStoredCurrentShareThenSnapshotsNextShare() public {
        _grantControllerMinterRole();
        _activateVoting();
        _setPreference(ALICE, WAD / 4);
        _deposit(ALICE, 100 ether);

        _warpToEpochEnd(0);
        controller.rollEpoch();

        assertEq(tech.balanceOf(SCIENCE_DISTRIBUTOR), 9 ether);
        assertEq(tech.balanceOf(RESEARCH_DISTRIBUTOR), 0);
        assertEq(controller.currentEpoch(), 1);
        assertEq(controller.currentScienceShareWad(), WAD / 4);
    }

    function test_rollEpochRoundsScienceDownAndSendsRemainderToResearch() public {
        controller = new TechEmissionController(
            address(tech),
            address(staking),
            SCIENCE_DISTRIBUTOR,
            RESEARCH_DISTRIBUTOR,
            EPOCH_DURATION,
            HALVING_INTERVAL,
            5,
            OWNER
        );
        _grantControllerMinterRole();
        _activateVoting();
        _setPreference(ALICE, WAD / 3);
        _deposit(ALICE, 9 ether);

        _warpToEpochEnd(0);
        controller.rollEpoch();

        _warpToEpochEnd(0);
        controller.rollEpoch();

        assertEq(tech.balanceOf(SCIENCE_DISTRIBUTOR), 6);
        assertEq(tech.balanceOf(RESEARCH_DISTRIBUTOR), 4);
    }

    function test_rollEpochAppliesHalvingAtConfiguredIntervals() public view {
        assertEq(controller.emissionForEpoch(0), 9 ether);
        assertEq(controller.emissionForEpoch(1), 9 ether);
        assertEq(controller.emissionForEpoch(2), 4.5 ether);
        assertEq(controller.emissionForEpoch(3), 4.5 ether);
        assertEq(controller.emissionForEpoch(4), 2.25 ether);
    }

    function test_bootstrapEpochStartsAtFullScienceEvenWhenStakingShareIsLower() public {
        _grantControllerMinterRole();
        _activateVoting();
        _setPreference(ALICE, 0);
        _deposit(ALICE, 100 ether);

        assertEq(controller.currentScienceShareWad(), WAD);
        assertEq(controller.previewNextScienceShareWad(), 0);

        _warpToEpochEnd(0);
        controller.rollEpoch();

        assertEq(tech.balanceOf(SCIENCE_DISTRIBUTOR), 9 ether);
        assertEq(controller.currentScienceShareWad(), 0);
    }

    function test_setDistributorsOnlyOwner() public {
        vm.prank(ALICE);
        vm.expectRevert();
        controller.setDistributors(ALICE, BOB);
    }

    function test_setDistributorsRejectsZeroAddresses() public {
        vm.prank(OWNER);
        vm.expectRevert(bytes("scienceDist=0"));
        controller.setDistributors(address(0), BOB);

        vm.prank(OWNER);
        vm.expectRevert(bytes("rrDist=0"));
        controller.setDistributors(ALICE, address(0));
    }

    function test_constructorRejectsZeroTechAddress() public {
        vm.expectRevert(bytes("TECH=0"));
        new TechEmissionController(
            address(0),
            address(staking),
            SCIENCE_DISTRIBUTOR,
            RESEARCH_DISTRIBUTOR,
            EPOCH_DURATION,
            HALVING_INTERVAL,
            9 ether,
            OWNER
        );
    }

    function test_constructorRejectsZeroStakingAddress() public {
        vm.expectRevert(bytes("STAKING=0"));
        new TechEmissionController(
            address(tech),
            address(0),
            SCIENCE_DISTRIBUTOR,
            RESEARCH_DISTRIBUTOR,
            EPOCH_DURATION,
            HALVING_INTERVAL,
            9 ether,
            OWNER
        );
    }

    function test_constructorRejectsZeroEpochDuration() public {
        vm.expectRevert(bytes("epoch=0"));
        new TechEmissionController(
            address(tech),
            address(staking),
            SCIENCE_DISTRIBUTOR,
            RESEARCH_DISTRIBUTOR,
            0,
            HALVING_INTERVAL,
            9 ether,
            OWNER
        );
    }

    function test_constructorRejectsZeroHalvingInterval() public {
        vm.expectRevert(bytes("halving=0"));
        new TechEmissionController(
            address(tech),
            address(staking),
            SCIENCE_DISTRIBUTOR,
            RESEARCH_DISTRIBUTOR,
            EPOCH_DURATION,
            0,
            9 ether,
            OWNER
        );
    }

    function test_emissionControllerRevertsWithoutMinterRole() public {
        _warpToEpochEnd(0);

        vm.expectRevert();
        controller.rollEpoch();
    }

    function test_emissionControllerCanMintAfterRoleGrant() public {
        _grantControllerMinterRole();
        _warpToEpochEnd(0);
        controller.rollEpoch();

        assertEq(tech.balanceOf(SCIENCE_DISTRIBUTOR), 9 ether);
    }

    function test_lateRollStartsNextEpochAtCallTimeAndBlocksImmediateReroll() public {
        _grantControllerMinterRole();
        _activateVoting();
        _setPreference(ALICE, 0);
        _deposit(ALICE, 50 ether);

        _warpToEpochEnd(3 hours);
        uint256 lateTimestamp = block.timestamp;
        controller.rollEpoch();

        assertEq(controller.currentEpochStart(), lateTimestamp);
        assertEq(controller.currentScienceShareWad(), 0);

        vm.expectRevert(bytes("epoch active"));
        controller.rollEpoch();
    }

    function test_lateRollLocksNextShareFromCallTime() public {
        _grantControllerMinterRole();
        _activateVoting();
        _deposit(ALICE, 100 ether);

        _warpToEpochEnd(2 hours);
        uint256 lateTimestamp = block.timestamp;

        _setPreference(ALICE, 0);
        controller.rollEpoch();

        assertEq(tech.balanceOf(SCIENCE_DISTRIBUTOR), 9 ether);
        assertEq(controller.currentScienceShareWad(), 0);
        assertEq(controller.currentEpochStart(), lateTimestamp);

        _setPreference(ALICE, WAD);
        vm.warp(lateTimestamp + EPOCH_DURATION);
        controller.rollEpoch();

        assertEq(tech.balanceOf(SCIENCE_DISTRIBUTOR), 9 ether);
        assertEq(tech.balanceOf(RESEARCH_DISTRIBUTOR), 9 ether);
        assertEq(controller.currentScienceShareWad(), WAD);
    }
}
