// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { TechContractsBase } from "../utils/TechContractsBase.sol";

contract TechStakingVoteUnitTest is TechContractsBase {
    function setUp() public {
        _deployVotingStack();

        _fundAndApprove(ALICE, 1_000 ether);
        _fundAndApprove(BOB, 1_000 ether);
        _fundAndApprove(CAROL, 1_000 ether);
    }

    function test_beforeActivationShareIsAlwaysFullScience() public {
        _deposit(ALICE, 100 ether);
        _setPreference(ALICE, 0);

        assertEq(staking.totalScienceWeighted(), 0);
        assertEq(staking.currentScienceShareWad(), WAD);
        assertEq(staking.currentResearchRevenueShareWad(), 0);
    }

    function test_afterActivationAndZeroSupplyShareIsStillFullScience() public {
        _activateVoting();

        assertEq(staking.totalSupply(), 0);
        assertEq(staking.currentScienceShareWad(), WAD);
        assertEq(staking.currentResearchRevenueShareWad(), 0);
    }

    function test_zeroStakeAccountCanSetPreferenceAndItAppliesToLaterDeposit() public {
        _setPreference(ALICE, 0);
        _deposit(ALICE, 50 ether);

        assertEq(staking.totalScienceWeighted(), 0);
        assertEq(staking.sciencePreferenceWad(ALICE), 0);
    }

    function test_fullWithdrawKeepsExplicitPreferenceForFutureDeposit() public {
        _setPreference(ALICE, 0);
        _deposit(ALICE, 50 ether);
        _withdraw(ALICE, 50 ether, ALICE);

        assertEq(staking.balanceOf(ALICE), 0);
        assertEq(staking.sciencePreferenceWad(ALICE), 0);

        _deposit(ALICE, 25 ether);

        assertEq(staking.balanceOf(ALICE), 25 ether);
        assertEq(staking.totalScienceWeighted(), 0);
    }

    function test_depositForUsesReceiverPreferenceNotCallerPreference() public {
        _setPreference(ALICE, 0);
        _depositFor(ALICE, BOB, 40 ether);

        assertEq(staking.balanceOf(BOB), 40 ether);
        assertEq(staking.totalScienceWeighted(), 40 ether);
    }

    function test_depositAndSetPreferenceMatchesSeparateCalls() public {
        _depositAndSetPreference(ALICE, 20 ether, WAD / 4);

        assertEq(staking.balanceOf(ALICE), 20 ether);
        assertEq(staking.sciencePreferenceWad(ALICE), WAD / 4);
        assertEq(staking.totalScienceWeighted(), 5 ether);
    }

    function test_withdrawToZeroAddressReverts() public {
        _deposit(ALICE, 10 ether);

        vm.prank(ALICE);
        vm.expectRevert(bytes("receiver=0"));
        staking.withdraw(10 ether, address(0));
    }

    function test_depositZeroReverts() public {
        vm.prank(ALICE);
        vm.expectRevert(bytes("amount=0"));
        staking.deposit(0);
    }

    function test_depositForZeroReceiverReverts() public {
        vm.prank(ALICE);
        vm.expectRevert(bytes("receiver=0"));
        staking.depositFor(address(0), 1 ether);
    }

    function test_preferenceAboveOneReverts() public {
        vm.prank(ALICE);
        vm.expectRevert(bytes("pref>1"));
        staking.setPreference(WAD + 1);
    }

    function test_activateVotingOnlyOwner() public {
        vm.prank(ALICE);
        vm.expectRevert();
        staking.activateVoting();
    }

    function test_activateVotingOnlyOnce() public {
        _activateVoting();

        vm.prank(OWNER);
        vm.expectRevert(bytes("already activated"));
        staking.activateVoting();
    }
}
