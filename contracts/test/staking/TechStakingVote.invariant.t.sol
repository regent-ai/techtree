// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { StdInvariant } from "forge-std/StdInvariant.sol";

import { StakingHandler } from "../helpers/StakingHandler.sol";
import { TechContractsBase } from "../utils/TechContractsBase.sol";

contract TechStakingVoteInvariantTest is StdInvariant, TechContractsBase {
    StakingHandler internal handler;
    address[] internal tracked;

    function setUp() public {
        _deployVotingStack();
        tracked = _trackedActors();

        _fundAndApprove(ALICE, 10_000 ether);
        _fundAndApprove(BOB, 10_000 ether);
        _fundAndApprove(CAROL, 10_000 ether);

        handler = new StakingHandler(tech, staking, OWNER, tracked);
        targetContract(address(handler));
    }

    function invariant_totalScienceWeightedNeverExceedsTotalSupply() public view {
        assertLe(staking.totalScienceWeighted(), staking.totalSupply());
    }

    function invariant_totalScienceWeightedEqualsManualRecomputationForTrackedActors() public view {
        assertEq(staking.totalScienceWeighted(), _manualWeightedTotal(tracked));
    }

    function invariant_underlyingTechBalanceEqualsStTechSupply() public view {
        assertEq(tech.balanceOf(address(staking)), staking.totalSupply());
    }

    function invariant_shareIsFullScienceWhenNotActivated() public view {
        if (!staking.votingActivated()) {
            assertEq(staking.currentScienceShareWad(), WAD);
        }
    }

    function invariant_shareIsFullScienceWhenSupplyIsZero() public view {
        if (staking.totalSupply() == 0) {
            assertEq(staking.currentScienceShareWad(), WAD);
        }
    }
}
