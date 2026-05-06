// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IAgentRegistryLike {
    function ownerOf(uint256 agentId) external view returns (address);
}
