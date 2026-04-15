// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ITechTreeRegistry } from "./ITechTreeRegistry.sol";

/// @title TechTreeRegistry
/// @notice Minimal Base registry for content-addressed TechTree nodes.
contract TechTreeRegistry is ITechTreeRegistry {
    mapping(bytes32 => NodeHeaderV1) public headers;

    error ZeroNodeId();
    error DuplicateNode(bytes32 id);
    error ZeroAuthor();
    error AuthorMismatch(address expected, address actual);
    error InvalidNodeType(uint8 nodeType);
    error InvalidSchemaVersion(uint16 schemaVersion);

    function publishNode(
        NodeHeaderV1 calldata header,
        bytes calldata manifestCid,
        bytes calldata payloadCid
    ) external {
        if (header.id == bytes32(0)) revert ZeroNodeId();
        if (headers[header.id].id != bytes32(0)) revert DuplicateNode(header.id);
        if (header.author == address(0)) revert ZeroAuthor();
        if (header.author != msg.sender) revert AuthorMismatch(header.author, msg.sender);
        if (header.nodeType < 1 || header.nodeType > 3) revert InvalidNodeType(header.nodeType);
        if (header.schemaVersion != 1) revert InvalidSchemaVersion(header.schemaVersion);

        headers[header.id] = header;

        emit NodePublished(header.id, header.nodeType, header.author, manifestCid, payloadCid);
    }

    function exists(bytes32 id) external view returns (bool) {
        return headers[id].id != bytes32(0);
    }

    function getHeader(bytes32 id) external view returns (NodeHeaderV1 memory) {
        return headers[id];
    }
}
