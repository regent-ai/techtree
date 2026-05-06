// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface ITechRewardRouter {
    function recordEpochBudget(
        uint64 epoch,
        uint256 totalEmission,
        uint256 scienceBudget,
        uint256 inputBudget
    ) external;
}
