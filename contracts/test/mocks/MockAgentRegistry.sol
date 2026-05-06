// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract MockAgentRegistry {
    mapping(uint256 => address) public owners;

    function setOwner(uint256 agentId, address owner) external {
        owners[agentId] = owner;
    }

    function ownerOf(uint256 agentId) external view returns (address) {
        address owner = owners[agentId];
        require(owner != address(0), "AGENT_MISSING");
        return owner;
    }
}
