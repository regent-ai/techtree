// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface ITechRewardVault {
    function creditLocked(uint256 agentId, uint256 amount, bytes32 sourceRef) external;
    function scienceShareWad() external view returns (uint256);
}
