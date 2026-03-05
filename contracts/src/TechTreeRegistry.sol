// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccessControlLite } from "./utils/AccessControlLite.sol";
import { PausableLite } from "./utils/PausableLite.sol";

/// @title TechTreeRegistry
/// @notice Anchors externally-assigned node IDs with manifest metadata.
contract TechTreeRegistry is AccessControlLite, PausableLite {
    bytes32 public constant WRITER_ROLE = keccak256("WRITER_ROLE");

    // Canonical order from revised v0.0.1 spec.
    enum NodeKind {
        Hypothesis,
        Data,
        Result,
        NullResult,
        Review,
        Synthesis,
        Meta,
        Skill
    }

    struct NodeAnchor {
        uint256 nodeId;
        uint256 parentId;
        address creator;
        string manifestUri;
        bytes32 manifestHash;
        NodeKind kind;
        uint64 createdAt;
        bool exists;
    }

    mapping(uint256 nodeId => NodeAnchor anchor) private _nodes;

    error ZeroAdmin();
    error NodeAlreadyExists(uint256 nodeId);
    error ParentDoesNotExist(uint256 parentId);
    error ZeroCreator();
    error EmptyManifestUri();

    event NodeCreated(
        uint256 indexed nodeId,
        uint256 indexed parentId,
        address indexed creator,
        address anchoredBy,
        string manifestUri,
        bytes32 manifestHash,
        uint8 kind,
        uint64 createdAt
    );

    constructor(address admin, address initialWriter) {
        if (admin == address(0)) revert ZeroAdmin();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        if (initialWriter != address(0)) {
            _grantRole(WRITER_ROLE, initialWriter);
        }
    }

    function createNode(
        uint256 nodeId,
        uint256 parentId,
        address creator,
        string calldata manifestUri,
        bytes32 manifestHash,
        NodeKind kind
    ) external onlyRole(WRITER_ROLE) whenNotPaused {
        if (_nodes[nodeId].exists) revert NodeAlreadyExists(nodeId);
        if (creator == address(0)) revert ZeroCreator();
        if (bytes(manifestUri).length == 0) revert EmptyManifestUri();
        if (parentId != 0 && !_nodes[parentId].exists) revert ParentDoesNotExist(parentId);

        uint64 createdAt = uint64(block.timestamp);
        _nodes[nodeId] = NodeAnchor({
            nodeId: nodeId,
            parentId: parentId,
            creator: creator,
            manifestUri: manifestUri,
            manifestHash: manifestHash,
            kind: kind,
            createdAt: createdAt,
            exists: true
        });

        emit NodeCreated(
            nodeId, parentId, creator, msg.sender, manifestUri, manifestHash, uint8(kind), createdAt
        );
    }

    function getNode(uint256 nodeId) external view returns (NodeAnchor memory) {
        return _nodes[nodeId];
    }

    function exists(uint256 nodeId) external view returns (bool) {
        return _nodes[nodeId].exists;
    }

    function grantWriter(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(WRITER_ROLE, account);
    }

    function revokeWriter(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(WRITER_ROLE, account);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
