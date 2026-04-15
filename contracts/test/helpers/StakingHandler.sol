// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { TechStakingVote } from "../../src/TechStakingVote.sol";
import { TechToken } from "../../src/TechToken.sol";
import { TestPreference } from "../utils/TestPreference.sol";

contract StakingHandler is Test {
    uint256 internal constant WAD = 1e18;

    TechToken internal immutable tech;
    TechStakingVote internal immutable staking;
    address internal immutable owner;
    address[] internal trackedActors;

    constructor(
        TechToken tech_,
        TechStakingVote staking_,
        address owner_,
        address[] memory actors_
    ) {
        tech = tech_;
        staking = staking_;
        owner = owner_;
        trackedActors = actors_;

        for (uint256 i = 0; i < trackedActors.length; i++) {
            vm.prank(trackedActors[i]);
            tech.approve(address(staking), type(uint256).max);
        }
    }

    function deposit(uint256 actorSeed, uint256 amountSeed) external {
        address actor = _actor(actorSeed);
        uint256 techBalance = tech.balanceOf(actor);
        if (techBalance == 0) return;

        uint256 amount = bound(amountSeed, 1, techBalance);
        vm.prank(actor);
        staking.deposit(amount);
    }

    function depositAndSetPreference(uint256 actorSeed, uint256 amountSeed, uint256 preferenceSeed)
        external
    {
        address actor = _actor(actorSeed);
        uint256 techBalance = tech.balanceOf(actor);
        if (techBalance == 0) return;

        uint256 amount = bound(amountSeed, 1, techBalance);
        uint256 preference = _boundedPreference(preferenceSeed);

        vm.prank(actor);
        staking.depositAndSetPreference(amount, preference);
    }

    function transferStake(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 stBalance = staking.balanceOf(from);
        if (stBalance == 0) return;

        uint256 amount = bound(amountSeed, 1, stBalance);
        vm.prank(from);
        staking.transfer(to, amount);
    }

    function withdraw(uint256 actorSeed, uint256 amountSeed) external {
        address actor = _actor(actorSeed);
        uint256 stBalance = staking.balanceOf(actor);
        if (stBalance == 0) return;

        uint256 amount = bound(amountSeed, 1, stBalance);
        vm.prank(actor);
        staking.withdraw(amount, actor);
    }

    function setPreference(uint256 actorSeed, uint256 preferenceSeed) external {
        address actor = _actor(actorSeed);
        uint256 preference = _boundedPreference(preferenceSeed);
        vm.prank(actor);
        staking.setPreference(preference);
    }

    function activateVoting() external {
        if (staking.votingActivated()) return;
        vm.prank(owner);
        staking.activateVoting();
    }

    function _actor(uint256 seed) internal view returns (address) {
        return trackedActors[seed % trackedActors.length];
    }

    function _boundedPreference(uint256 raw) internal pure returns (uint256) {
        return TestPreference.boundPreference(raw, WAD);
    }
}
