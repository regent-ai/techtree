// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ITechTreeRegistry } from "../src/ITechTreeRegistry.sol";
import { TechTreeRegistry } from "../src/TechTreeRegistry.sol";
import { TestBase } from "./utils/TestBase.sol";

contract TechTreeRegistryTest is TestBase {
    TechTreeRegistry internal registry;

    address internal constant AUTHOR = address(0xA11CE);
    address internal constant OTHER = address(0xD00D);

    bytes32 internal constant ARTIFACT_ID =
        0x7f8f2f5700db5a0b5cbec5f3668228f1f3149449f86b6f295d55f266f9af680d;
    bytes32 internal constant SUBJECT_ID =
        0x1c8c4fd69f4ed2b71c38c04f8f9246d0a501c61dd0ce0d0f4f649d2d0d8bc444;
    bytes32 internal constant AUX_ID =
        0x2e50fb4f01b54df68f7c15c62d2a9a1b4d1fd6ee9d3f4e8b00f5c1d30c8c4d2a;
    bytes32 internal constant PAYLOAD_HASH =
        0x3b6f6fbbac5f2f3b2f8f85d3a5db0d68ddc56e9ec0a0b1a0c6f4c9d8e5b1c123;
    string internal constant MANIFEST_CID = "bafybeigdyrztc4manifest";
    string internal constant PAYLOAD_CID = "bafybeifayloadbundle";

    function setUp() public {
        registry = new TechTreeRegistry();
    }

    function testExistsReturnsFalseForUnknownNode() public view {
        assertEq(registry.exists(bytes32(uint256(999))), false, "unknown node should not exist");
    }

    function testGetHeaderReturnsDefaultForUnknownNode() public view {
        ITechTreeRegistry.NodeHeaderV1 memory header = registry.getHeader(bytes32(uint256(999)));
        assertEq(header.id, bytes32(0), "id should default to zero");
        assertEq(header.subjectId, bytes32(0), "subject should default to zero");
        assertEq(header.auxId, bytes32(0), "aux should default to zero");
        assertEq(header.payloadHash, bytes32(0), "payload hash should default to zero");
        assertEq(uint256(header.nodeType), 0, "node type should default to zero");
        assertEq(uint256(header.schemaVersion), 0, "schema version should default to zero");
        assertEq(uint256(header.flags), 0, "flags should default to zero");
        assertEq(header.author, address(0), "author should default to zero address");
    }

    function testPublishNodeStoresHeaderAndEmitsEvent() public {
        ITechTreeRegistry.NodeHeaderV1 memory header = ITechTreeRegistry.NodeHeaderV1({
            id: ARTIFACT_ID,
            subjectId: SUBJECT_ID,
            auxId: AUX_ID,
            payloadHash: PAYLOAD_HASH,
            nodeType: 1,
            schemaVersion: 1,
            flags: 0x00000003,
            author: AUTHOR
        });

        recordLogs();
        vm.prank(AUTHOR);
        registry.publishNode(header, bytes(MANIFEST_CID), bytes(PAYLOAD_CID));

        assertEq(registry.exists(ARTIFACT_ID), true, "node should exist");

        ITechTreeRegistry.NodeHeaderV1 memory stored = registry.getHeader(ARTIFACT_ID);
        assertEq(stored.id, header.id, "id mismatch");
        assertEq(stored.subjectId, header.subjectId, "subject mismatch");
        assertEq(stored.auxId, header.auxId, "aux mismatch");
        assertEq(stored.payloadHash, header.payloadHash, "payload hash mismatch");
        assertEq(uint256(stored.nodeType), uint256(header.nodeType), "node type mismatch");
        assertEq(uint256(stored.schemaVersion), uint256(header.schemaVersion), "schema mismatch");
        assertEq(uint256(stored.flags), uint256(header.flags), "flags mismatch");
        assertEq(stored.author, header.author, "author mismatch");

        (bytes32[] memory topics, bytes memory data, address emitter, uint256 logCount) =
            readRecordedLog(0);
        assertEq(logCount, 1, "expected exactly one event");
        assertEq(emitter, address(registry), "event emitter mismatch");
        assertEq(
            topics[0],
            keccak256("NodePublished(bytes32,uint8,address,bytes,bytes)"),
            "topic0 mismatch"
        );
        assertEq(topics[1], ARTIFACT_ID, "id topic mismatch");
        assertEq(uint256(topics[2]), uint256(uint8(header.nodeType)), "node type topic mismatch");
        assertEq(address(uint160(uint256(topics[3]))), AUTHOR, "author topic mismatch");

        (bytes memory emittedManifestCid, bytes memory emittedPayloadCid) =
            abi.decode(data, (bytes, bytes));
        assertEq(
            keccak256(emittedManifestCid), keccak256(bytes(MANIFEST_CID)), "manifest cid mismatch"
        );
        assertEq(
            keccak256(emittedPayloadCid), keccak256(bytes(PAYLOAD_CID)), "payload cid mismatch"
        );
    }

    function testPublishNodeAcceptsRunAndReviewTypes() public {
        ITechTreeRegistry.NodeHeaderV1 memory runHeader = ITechTreeRegistry.NodeHeaderV1({
            id: bytes32(uint256(2)),
            subjectId: ARTIFACT_ID,
            auxId: AUX_ID,
            payloadHash: PAYLOAD_HASH,
            nodeType: 2,
            schemaVersion: 1,
            flags: 0,
            author: AUTHOR
        });

        ITechTreeRegistry.NodeHeaderV1 memory reviewHeader = ITechTreeRegistry.NodeHeaderV1({
            id: bytes32(uint256(3)),
            subjectId: bytes32(uint256(2)),
            auxId: bytes32(uint256(4)),
            payloadHash: PAYLOAD_HASH,
            nodeType: 3,
            schemaVersion: 1,
            flags: 1,
            author: AUTHOR
        });

        vm.startPrank(AUTHOR);
        registry.publishNode(runHeader, bytes(MANIFEST_CID), bytes(PAYLOAD_CID));
        registry.publishNode(reviewHeader, bytes(MANIFEST_CID), bytes(PAYLOAD_CID));
        vm.stopPrank();

        assertEq(registry.exists(bytes32(uint256(2))), true, "run should exist");
        assertEq(registry.exists(bytes32(uint256(3))), true, "review should exist");
    }

    function testRevertIfNodeIdIsZero() public {
        ITechTreeRegistry.NodeHeaderV1 memory header = ITechTreeRegistry.NodeHeaderV1({
            id: bytes32(0),
            subjectId: SUBJECT_ID,
            auxId: AUX_ID,
            payloadHash: PAYLOAD_HASH,
            nodeType: 1,
            schemaVersion: 1,
            flags: 0,
            author: AUTHOR
        });

        vm.expectRevert(TechTreeRegistry.ZeroNodeId.selector);
        vm.prank(AUTHOR);
        registry.publishNode(header, bytes(MANIFEST_CID), bytes(PAYLOAD_CID));
    }

    function testRevertIfNodeAlreadyExists() public {
        ITechTreeRegistry.NodeHeaderV1 memory header = ITechTreeRegistry.NodeHeaderV1({
            id: ARTIFACT_ID,
            subjectId: SUBJECT_ID,
            auxId: AUX_ID,
            payloadHash: PAYLOAD_HASH,
            nodeType: 1,
            schemaVersion: 1,
            flags: 0,
            author: AUTHOR
        });

        vm.startPrank(AUTHOR);
        registry.publishNode(header, bytes(MANIFEST_CID), bytes(PAYLOAD_CID));
        vm.expectRevert(
            abi.encodeWithSelector(TechTreeRegistry.DuplicateNode.selector, ARTIFACT_ID)
        );
        registry.publishNode(header, bytes(MANIFEST_CID), bytes(PAYLOAD_CID));
        vm.stopPrank();
    }

    function testRevertIfAuthorIsZero() public {
        ITechTreeRegistry.NodeHeaderV1 memory header = ITechTreeRegistry.NodeHeaderV1({
            id: ARTIFACT_ID,
            subjectId: SUBJECT_ID,
            auxId: AUX_ID,
            payloadHash: PAYLOAD_HASH,
            nodeType: 1,
            schemaVersion: 1,
            flags: 0,
            author: address(0)
        });

        vm.expectRevert(TechTreeRegistry.ZeroAuthor.selector);
        registry.publishNode(header, bytes(MANIFEST_CID), bytes(PAYLOAD_CID));
    }

    function testRevertIfAuthorDoesNotMatchCaller() public {
        ITechTreeRegistry.NodeHeaderV1 memory header = ITechTreeRegistry.NodeHeaderV1({
            id: ARTIFACT_ID,
            subjectId: SUBJECT_ID,
            auxId: AUX_ID,
            payloadHash: PAYLOAD_HASH,
            nodeType: 1,
            schemaVersion: 1,
            flags: 0,
            author: AUTHOR
        });

        vm.expectRevert(
            abi.encodeWithSelector(TechTreeRegistry.AuthorMismatch.selector, AUTHOR, OTHER)
        );
        vm.prank(OTHER);
        registry.publishNode(header, bytes(MANIFEST_CID), bytes(PAYLOAD_CID));
    }

    function testRevertIfNodeTypeIsOutOfRange() public {
        ITechTreeRegistry.NodeHeaderV1 memory header = ITechTreeRegistry.NodeHeaderV1({
            id: ARTIFACT_ID,
            subjectId: SUBJECT_ID,
            auxId: AUX_ID,
            payloadHash: PAYLOAD_HASH,
            nodeType: 4,
            schemaVersion: 1,
            flags: 0,
            author: AUTHOR
        });

        vm.expectRevert(abi.encodeWithSelector(TechTreeRegistry.InvalidNodeType.selector, 4));
        vm.prank(AUTHOR);
        registry.publishNode(header, bytes(MANIFEST_CID), bytes(PAYLOAD_CID));
    }

    function testRevertIfSchemaVersionIsWrong() public {
        ITechTreeRegistry.NodeHeaderV1 memory header = ITechTreeRegistry.NodeHeaderV1({
            id: ARTIFACT_ID,
            subjectId: SUBJECT_ID,
            auxId: AUX_ID,
            payloadHash: PAYLOAD_HASH,
            nodeType: 1,
            schemaVersion: 2,
            flags: 0,
            author: AUTHOR
        });

        vm.expectRevert(abi.encodeWithSelector(TechTreeRegistry.InvalidSchemaVersion.selector, 2));
        vm.prank(AUTHOR);
        registry.publishNode(header, bytes(MANIFEST_CID), bytes(PAYLOAD_CID));
    }
}
