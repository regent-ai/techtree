// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ITechTreeRegistry } from "./ITechTreeRegistry.sol";

/// @title TechTreeRegistry
/// @notice Minimal Base registry for content-addressed TechTree nodes.
contract TechTreeRegistry is ITechTreeRegistry {
    mapping(bytes32 => NodeHeaderV1) public headers;
    mapping(address => bool) public publishers;
    address public owner;

    error ZeroNodeId();
    error DuplicateNode(bytes32 id);
    error ZeroAuthor();
    error ZeroAddress();
    error UnauthorizedPublisher(address publisher);
    error NotOwner(address caller);
    error InvalidNodeType(uint8 nodeType);
    error InvalidSchemaVersion(uint16 schemaVersion);

    constructor() {
        owner = msg.sender;
        publishers[msg.sender] = true;

        emit OwnershipTransferred(address(0), msg.sender);
        emit PublisherSet(msg.sender, true);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner(msg.sender);
        _;
    }

    function publishNode(
        NodeHeaderV1 calldata header,
        bytes calldata manifestCid,
        bytes calldata payloadCid
    ) external {
        if (header.id == bytes32(0)) revert ZeroNodeId();
        if (headers[header.id].id != bytes32(0)) revert DuplicateNode(header.id);
        if (header.author == address(0)) revert ZeroAuthor();
        if (header.author != msg.sender && !publishers[msg.sender]) {
            revert UnauthorizedPublisher(msg.sender);
        }
        if (header.nodeType < 1 || header.nodeType > 3) revert InvalidNodeType(header.nodeType);
        if (header.schemaVersion != 1) revert InvalidSchemaVersion(header.schemaVersion);

        headers[header.id] = header;

        emit NodePublished(header.id, header.nodeType, header.author, manifestCid, payloadCid);
    }

    function setPublisher(address publisher, bool allowed) external onlyOwner {
        if (publisher == address(0)) revert ZeroAddress();
        publishers[publisher] = allowed;
        emit PublisherSet(publisher, allowed);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        address previousOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }

    function exists(bytes32 id) external view returns (bool) {
        return headers[id].id != bytes32(0);
    }

    function getHeader(bytes32 id) external view returns (NodeHeaderV1 memory) {
        return headers[id];
    }
}
