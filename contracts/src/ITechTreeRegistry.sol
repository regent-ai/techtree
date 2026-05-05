// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ITechTreeRegistry {
    struct NodeHeaderV1 {
        bytes32 id;
        bytes32 subjectId;
        bytes32 auxId;
        bytes32 payloadHash;
        uint8 nodeType;
        uint16 schemaVersion;
        uint32 flags;
        address author;
    }

    event NodePublished(
        bytes32 indexed id,
        uint8 indexed nodeType,
        address indexed author,
        bytes manifestCid,
        bytes payloadCid
    );

    event PublisherSet(address indexed publisher, bool allowed);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function publishNode(
        NodeHeaderV1 calldata header,
        bytes calldata manifestCid,
        bytes calldata payloadCid
    ) external;

    function setPublisher(address publisher, bool allowed) external;

    function transferOwnership(address newOwner) external;

    function owner() external view returns (address);

    function publishers(address publisher) external view returns (bool);

    function exists(bytes32 id) external view returns (bool);

    function getHeader(bytes32 id) external view returns (NodeHeaderV1 memory);
}
