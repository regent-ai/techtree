// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { TechContractsBase } from "../utils/TechContractsBase.sol";

contract TechStakingVoteFuzzTest is TechContractsBase {
    function setUp() public {
        _deployVotingStack();

        _fundAndApprove(ALICE, 2_000 ether);
        _fundAndApprove(BOB, 2_000 ether);
        _fundAndApprove(CAROL, 2_000 ether);
    }

    function testFuzz_transferUpdatesScienceWeightExactly(
        uint256 aliceDeposit,
        uint256 bobDeposit,
        uint256 alicePreferenceSeed,
        uint256 bobPreferenceSeed,
        uint256 transferAmount
    ) public {
        aliceDeposit = bound(aliceDeposit, 1 ether, 1_000 ether);
        bobDeposit = bound(bobDeposit, 1 ether, 1_000 ether);

        uint256 alicePreference = _boundedPreference(alicePreferenceSeed);
        uint256 bobPreference = _boundedPreference(bobPreferenceSeed);

        _setPreference(ALICE, alicePreference);
        _setPreference(BOB, bobPreference);
        _deposit(ALICE, aliceDeposit);
        _deposit(BOB, bobDeposit);

        transferAmount = bound(transferAmount, 1, aliceDeposit);
        vm.prank(ALICE);
        staking.transfer(BOB, transferAmount);

        assertEq(staking.totalScienceWeighted(), _manualWeightedTotal(_trackedActors()));
    }

    function testFuzz_setPreferenceUpdatesScienceWeightExactly(
        uint256 depositAmount,
        uint256 oldPreferenceSeed,
        uint256 newPreferenceSeed
    ) public {
        depositAmount = bound(depositAmount, 1 ether, 1_000 ether);

        uint256 oldPreference = _boundedPreference(oldPreferenceSeed);
        uint256 newPreference = _boundedPreference(newPreferenceSeed);

        _setPreference(ALICE, oldPreference);
        _deposit(ALICE, depositAmount);

        vm.prank(ALICE);
        staking.setPreference(newPreference);

        uint256 expected = depositAmount * newPreference / WAD;
        assertEq(staking.totalScienceWeighted(), expected);
        assertEq(staking.totalScienceWeighted(), _manualWeightedTotal(_trackedActors()));
    }

    function testFuzz_transferToSelfKeepsScienceWeightUnchanged(
        uint256 depositAmount,
        uint256 preferenceSeed,
        uint256 transferAmount
    ) public {
        depositAmount = bound(depositAmount, 1 ether, 1_000 ether);

        uint256 preference = _boundedPreference(preferenceSeed);
        _setPreference(ALICE, preference);
        _deposit(ALICE, depositAmount);

        uint256 beforeWeighted = staking.totalScienceWeighted();
        uint256 beforeShare = staking.currentScienceShareWad();

        transferAmount = bound(transferAmount, 1, depositAmount);
        vm.prank(ALICE);
        staking.transfer(ALICE, transferAmount);

        assertEq(staking.totalScienceWeighted(), beforeWeighted);
        assertEq(staking.currentScienceShareWad(), beforeShare);
    }

    function testFuzz_sequence_depositTransferWithdrawKeepsExactWeight(
        uint256 depositAmount,
        uint256 alicePreferenceSeed,
        uint256 bobPreferenceSeed,
        uint256 carolPreferenceSeed,
        uint256 transferAmount,
        uint256 withdrawAmount
    ) public {
        depositAmount = bound(depositAmount, 3 ether, 900 ether);

        _setPreference(ALICE, _boundedPreference(alicePreferenceSeed));
        _setPreference(BOB, _boundedPreference(bobPreferenceSeed));
        _setPreference(CAROL, _boundedPreference(carolPreferenceSeed));

        _deposit(ALICE, depositAmount);
        assertEq(staking.totalScienceWeighted(), _manualWeightedTotal(_trackedActors()));

        transferAmount = bound(transferAmount, 1, depositAmount / 2);
        vm.prank(ALICE);
        staking.transfer(BOB, transferAmount);
        assertEq(staking.totalScienceWeighted(), _manualWeightedTotal(_trackedActors()));

        _deposit(CAROL, depositAmount / 3);
        assertEq(staking.totalScienceWeighted(), _manualWeightedTotal(_trackedActors()));

        withdrawAmount = bound(withdrawAmount, 1, staking.balanceOf(BOB));
        _withdraw(BOB, withdrawAmount, BOB);
        assertEq(staking.totalScienceWeighted(), _manualWeightedTotal(_trackedActors()));

        uint256 updatedCarolPreferenceSeed =
            carolPreferenceSeed == type(uint256).max ? 0 : carolPreferenceSeed + 1;

        vm.prank(CAROL);
        staking.setPreference(_boundedPreference(updatedCarolPreferenceSeed));
        assertEq(staking.totalScienceWeighted(), _manualWeightedTotal(_trackedActors()));
    }
}
