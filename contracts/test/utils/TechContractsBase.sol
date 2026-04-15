// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { TechEmissionController } from "../../src/TechEmissionController.sol";
import { TechStakingVote } from "../../src/TechStakingVote.sol";
import { TechToken } from "../../src/TechToken.sol";
import { TestPreference } from "./TestPreference.sol";

contract TechContractsBase is Test {
    uint256 internal constant WAD = 1e18;

    address internal constant ADMIN = address(0xA11CE);
    address internal constant OWNER = address(0xB0B);
    address internal constant ALICE = address(0xA11CE1);
    address internal constant BOB = address(0xB0B1);
    address internal constant CAROL = address(0xCA501);
    address internal constant SCIENCE_DISTRIBUTOR = address(0x51E11CE);
    address internal constant RESEARCH_DISTRIBUTOR = address(0xABCDEF2);
    address internal constant RANDOM_CALLER = address(0xFEE1);

    TechToken internal tech;
    TechStakingVote internal staking;
    TechEmissionController internal controller;

    function _deployToken() internal {
        tech = new TechToken(ADMIN);
    }

    function _deployStaking() internal {
        staking = new TechStakingVote(address(tech), OWNER);
    }

    function _deployVotingStack() internal {
        _deployToken();
        _deployStaking();
    }

    function _deployController(
        uint64 epochDuration,
        uint64 halvingIntervalEpochs,
        uint256 initialEpochEmission
    ) internal {
        controller = new TechEmissionController(
            address(tech),
            address(staking),
            SCIENCE_DISTRIBUTOR,
            RESEARCH_DISTRIBUTOR,
            epochDuration,
            halvingIntervalEpochs,
            initialEpochEmission,
            OWNER
        );
    }

    function _mintTech(address to, uint256 amount) internal {
        vm.prank(ADMIN);
        tech.mint(to, amount);
    }

    function _approveStake(address account) internal {
        vm.prank(account);
        tech.approve(address(staking), type(uint256).max);
    }

    function _fundAndApprove(address account, uint256 amount) internal {
        _mintTech(account, amount);
        _approveStake(account);
    }

    function _setPreference(address account, uint256 preferenceWad) internal {
        vm.prank(account);
        staking.setPreference(preferenceWad);
    }

    function _deposit(address account, uint256 amount) internal {
        vm.prank(account);
        staking.deposit(amount);
    }

    function _depositFor(address caller, address receiver, uint256 amount) internal {
        vm.prank(caller);
        staking.depositFor(receiver, amount);
    }

    function _depositAndSetPreference(address account, uint256 amount, uint256 preferenceWad)
        internal
    {
        vm.prank(account);
        staking.depositAndSetPreference(amount, preferenceWad);
    }

    function _withdraw(address account, uint256 amount, address receiver) internal {
        vm.prank(account);
        staking.withdraw(amount, receiver);
    }

    function _activateVoting() internal {
        vm.prank(OWNER);
        staking.activateVoting();
    }

    function _grantMinterRole(address account) internal {
        bytes32 minterRole = tech.MINTER_ROLE();
        vm.prank(ADMIN);
        tech.grantRole(minterRole, account);
    }

    function _grantControllerMinterRole() internal {
        _grantMinterRole(address(controller));
    }

    function _warpToEpochEnd(uint256 extraDelay) internal {
        vm.warp(
            uint256(controller.currentEpochStart()) + uint256(controller.epochDuration())
                + extraDelay
        );
    }

    function _boundedPreference(uint256 raw) internal pure returns (uint256) {
        return TestPreference.boundPreference(raw, WAD);
    }

    function _trackedActors() internal pure returns (address[] memory accounts) {
        accounts = new address[](3);
        accounts[0] = ALICE;
        accounts[1] = BOB;
        accounts[2] = CAROL;
    }

    function _manualContribution(address account) internal view returns (uint256) {
        return staking.balanceOf(account) * staking.sciencePreferenceWad(account) / WAD;
    }

    function _manualWeightedTotal(address[] memory accounts) internal view returns (uint256 total) {
        for (uint256 i = 0; i < accounts.length; i++) {
            total += _manualContribution(accounts[i]);
        }
    }
}
