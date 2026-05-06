// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

contract TechLeaderboardRegistry is AccessControl {
    bytes32 public constant LEADERBOARD_MANAGER_ROLE = keccak256("LEADERBOARD_MANAGER_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    struct Leaderboard {
        bytes32 id;
        uint8 kind;
        uint16 weightBps;
        uint64 startsEpoch;
        uint64 endsEpoch;
        bytes32 configHash;
        string uri;
        bool active;
    }

    mapping(bytes32 => Leaderboard) private _leaderboards;

    event LeaderboardRegistered(
        bytes32 indexed id, uint8 kind, uint16 weightBps, bytes32 configHash, string uri
    );
    event LeaderboardUpdated(
        bytes32 indexed id, uint16 weightBps, bytes32 configHash, string uri, bool active
    );
    event LeaderboardStatusSet(bytes32 indexed id, bool active);
    event LeaderboardGovernanceTransferred(address indexed oldManager, address indexed newManager);

    error ZeroAddress();
    error IdZero();
    error ConfigHashZero();
    error UriEmpty();
    error WeightTooHigh();
    error DuplicateLeaderboard();
    error LeaderboardMissing();

    constructor(address admin_) {
        if (admin_ == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(GOVERNANCE_ROLE, admin_);
        _grantRole(LEADERBOARD_MANAGER_ROLE, admin_);
    }

    function registerLeaderboard(Leaderboard calldata leaderboard)
        external
        onlyRole(LEADERBOARD_MANAGER_ROLE)
    {
        _validateNewLeaderboard(leaderboard);
        _leaderboards[leaderboard.id] = leaderboard;

        emit LeaderboardRegistered(
            leaderboard.id,
            leaderboard.kind,
            leaderboard.weightBps,
            leaderboard.configHash,
            leaderboard.uri
        );
    }

    function updateLeaderboard(
        bytes32 id,
        uint16 weightBps,
        bytes32 configHash,
        string calldata uri
    ) external onlyRole(LEADERBOARD_MANAGER_ROLE) {
        Leaderboard storage leaderboard = _leaderboards[id];
        if (leaderboard.id == bytes32(0)) revert LeaderboardMissing();
        if (weightBps > 10_000) revert WeightTooHigh();
        if (configHash == bytes32(0)) revert ConfigHashZero();
        if (bytes(uri).length == 0) revert UriEmpty();

        leaderboard.weightBps = weightBps;
        leaderboard.configHash = configHash;
        leaderboard.uri = uri;

        emit LeaderboardUpdated(id, weightBps, configHash, uri, leaderboard.active);
    }

    function setLeaderboardActive(bytes32 id, bool active)
        external
        onlyRole(LEADERBOARD_MANAGER_ROLE)
    {
        Leaderboard storage leaderboard = _leaderboards[id];
        if (leaderboard.id == bytes32(0)) revert LeaderboardMissing();
        leaderboard.active = active;
        emit LeaderboardStatusSet(id, active);
    }

    function transferLeaderboardManager(address oldManager, address newManager)
        external
        onlyRole(GOVERNANCE_ROLE)
    {
        if (oldManager == address(0) || newManager == address(0)) revert ZeroAddress();
        _revokeRole(LEADERBOARD_MANAGER_ROLE, oldManager);
        _grantRole(LEADERBOARD_MANAGER_ROLE, newManager);
        emit LeaderboardGovernanceTransferred(oldManager, newManager);
    }

    function getLeaderboard(bytes32 id) external view returns (Leaderboard memory) {
        Leaderboard memory leaderboard = _leaderboards[id];
        if (leaderboard.id == bytes32(0)) revert LeaderboardMissing();
        return leaderboard;
    }

    function _validateNewLeaderboard(Leaderboard calldata leaderboard) internal view {
        if (leaderboard.id == bytes32(0)) revert IdZero();
        if (_leaderboards[leaderboard.id].id != bytes32(0)) revert DuplicateLeaderboard();
        if (leaderboard.weightBps > 10_000) revert WeightTooHigh();
        if (leaderboard.configHash == bytes32(0)) revert ConfigHashZero();
        if (bytes(leaderboard.uri).length == 0) revert UriEmpty();
    }
}
