// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { TechTreeRegistry } from "../src/TechTreeRegistry.sol";
import { AccessControlLite } from "../src/utils/AccessControlLite.sol";
import { PausableLite } from "../src/utils/PausableLite.sol";
import { TestBase } from "./utils/TestBase.sol";

contract TechTreeRegistryTest is TestBase {
    TechTreeRegistry internal registry;

    address internal constant ADMIN = address(0xA11CE);
    address internal constant WRITER = address(0xB0B);
    address internal constant CREATOR = address(0xC0FFEE);
    address internal constant OTHER = address(0xD00D);
    address internal constant WRITER_TWO = address(0xE77E);

    bytes32 internal constant MANIFEST_HASH =
        0x7f8f2f5700db5a0b5cbec5f3668228f1f3149449f86b6f295d55f266f9af680d;
    string internal constant MANIFEST_URI = "ipfs://bafybeigdyrztc4manifest";

    function setUp() public {
        registry = new TechTreeRegistry(ADMIN, WRITER);
    }

    function testRevertIfAdminIsZero() public {
        vm.expectRevert(TechTreeRegistry.ZeroAdmin.selector);
        new TechTreeRegistry(address(0), WRITER);
    }

    function testNodeKindCanonicalOrder() public pure {
        assertEq(uint256(uint8(TechTreeRegistry.NodeKind.Hypothesis)), 0, "Hypothesis must be 0");
        assertEq(uint256(uint8(TechTreeRegistry.NodeKind.Data)), 1, "Data must be 1");
        assertEq(uint256(uint8(TechTreeRegistry.NodeKind.Result)), 2, "Result must be 2");
        assertEq(uint256(uint8(TechTreeRegistry.NodeKind.NullResult)), 3, "NullResult must be 3");
        assertEq(uint256(uint8(TechTreeRegistry.NodeKind.Review)), 4, "Review must be 4");
        assertEq(uint256(uint8(TechTreeRegistry.NodeKind.Synthesis)), 5, "Synthesis must be 5");
        assertEq(uint256(uint8(TechTreeRegistry.NodeKind.Meta)), 6, "Meta must be 6");
        assertEq(uint256(uint8(TechTreeRegistry.NodeKind.Skill)), 7, "Skill must be 7");
    }

    function testCreateRootNodeSuccess() public {
        vm.prank(WRITER);
        registry.createNode(
            1, 0, CREATOR, MANIFEST_URI, MANIFEST_HASH, TechTreeRegistry.NodeKind.Hypothesis
        );

        assertEq(registry.exists(1), true, "node 1 must exist");

        TechTreeRegistry.NodeAnchor memory node = registry.getNode(1);
        assertEq(node.nodeId, 1, "node id mismatch");
        assertEq(node.parentId, 0, "parent should be root");
        assertEq(node.creator, CREATOR, "creator mismatch");
        assertEq(node.manifestUri, MANIFEST_URI, "manifest URI mismatch");
        assertEq(node.manifestHash, MANIFEST_HASH, "manifest hash mismatch");
        assertEq(
            uint256(uint8(node.kind)),
            uint256(uint8(TechTreeRegistry.NodeKind.Hypothesis)),
            "kind mismatch"
        );
        assertTrue(node.createdAt > 0, "createdAt should be set");
        assertEq(node.exists, true, "exists flag mismatch");
    }

    function testNodeCreatedEventCarriesCanonicalAnchorFields() public {
        vm.prank(WRITER);
        registry.createNode(
            11, 0, CREATOR, "ipfs://bafybei-parent", MANIFEST_HASH, TechTreeRegistry.NodeKind.Data
        );

        recordLogs();
        vm.prank(WRITER);
        registry.createNode(
            77, 11, CREATOR, MANIFEST_URI, MANIFEST_HASH, TechTreeRegistry.NodeKind.Review
        );

        (bytes32[] memory topics, bytes memory data, address emitter, uint256 logCount) =
            readRecordedLog(0);
        assertEq(logCount, 1, "expected exactly one event");
        assertEq(emitter, address(registry), "event emitter must be registry");
        assertEq(
            topics[0],
            keccak256("NodeCreated(uint256,uint256,address,address,string,bytes32,uint8,uint64)"),
            "topic0 mismatch"
        );
        assertEq(uint256(topics[1]), 77, "nodeId topic mismatch");
        assertEq(uint256(topics[2]), 11, "parentId topic mismatch");
        assertEq(address(uint160(uint256(topics[3]))), CREATOR, "creator topic mismatch");

        (
            address anchoredBy,
            string memory manifestUri,
            bytes32 manifestHash,
            uint8 kind,
            uint64 createdAt
        ) = abi.decode(data, (address, string, bytes32, uint8, uint64));

        assertEq(anchoredBy, WRITER, "anchoredBy mismatch");
        assertEq(manifestUri, MANIFEST_URI, "manifest URI mismatch");
        assertEq(manifestHash, MANIFEST_HASH, "manifest hash mismatch");
        assertEq(uint256(kind), uint256(uint8(TechTreeRegistry.NodeKind.Review)), "kind mismatch");
        assertTrue(createdAt > 0, "createdAt must be non-zero");
    }

    function testCreateChildSuccessWhenParentExists() public {
        vm.startPrank(WRITER);
        registry.createNode(
            100, 0, CREATOR, MANIFEST_URI, MANIFEST_HASH, TechTreeRegistry.NodeKind.Data
        );
        registry.createNode(
            101,
            100,
            CREATOR,
            "ipfs://bafybeichildmanifest",
            bytes32(uint256(0x1234)),
            TechTreeRegistry.NodeKind.Result
        );
        vm.stopPrank();

        TechTreeRegistry.NodeAnchor memory child = registry.getNode(101);
        assertEq(child.parentId, 100, "child parent mismatch");
        assertEq(
            uint256(uint8(child.kind)),
            uint256(uint8(TechTreeRegistry.NodeKind.Result)),
            "kind mismatch"
        );
        assertEq(child.exists, true, "child exists mismatch");
    }

    function testRevertIfNonWriterCreatesNode() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlLite.AccessControlUnauthorizedAccount.selector,
                OTHER,
                registry.WRITER_ROLE()
            )
        );
        vm.prank(OTHER);
        registry.createNode(
            1, 0, CREATOR, MANIFEST_URI, MANIFEST_HASH, TechTreeRegistry.NodeKind.Data
        );
    }

    function testRevertIfNodeAlreadyExists() public {
        vm.startPrank(WRITER);
        registry.createNode(
            1, 0, CREATOR, MANIFEST_URI, MANIFEST_HASH, TechTreeRegistry.NodeKind.Data
        );
        vm.expectRevert(abi.encodeWithSelector(TechTreeRegistry.NodeAlreadyExists.selector, 1));
        registry.createNode(
            1, 0, CREATOR, MANIFEST_URI, MANIFEST_HASH, TechTreeRegistry.NodeKind.Data
        );
        vm.stopPrank();
    }

    function testRevertIfParentDoesNotExist() public {
        vm.prank(WRITER);
        vm.expectRevert(abi.encodeWithSelector(TechTreeRegistry.ParentDoesNotExist.selector, 999));
        registry.createNode(
            2, 999, CREATOR, MANIFEST_URI, MANIFEST_HASH, TechTreeRegistry.NodeKind.Review
        );
    }

    function testRevertIfCreatorIsZero() public {
        vm.prank(WRITER);
        vm.expectRevert(TechTreeRegistry.ZeroCreator.selector);
        registry.createNode(
            1, 0, address(0), MANIFEST_URI, MANIFEST_HASH, TechTreeRegistry.NodeKind.NullResult
        );
    }

    function testRevertIfManifestUriIsEmpty() public {
        vm.prank(WRITER);
        vm.expectRevert(TechTreeRegistry.EmptyManifestUri.selector);
        registry.createNode(1, 0, CREATOR, "", MANIFEST_HASH, TechTreeRegistry.NodeKind.Synthesis);
    }

    function testPauseBlocksWritesAndUnpauseRestores() public {
        vm.prank(ADMIN);
        registry.pause();

        vm.prank(WRITER);
        vm.expectRevert(PausableLite.EnforcedPause.selector);
        registry.createNode(
            1, 0, CREATOR, MANIFEST_URI, MANIFEST_HASH, TechTreeRegistry.NodeKind.Meta
        );

        vm.prank(ADMIN);
        registry.unpause();

        vm.prank(WRITER);
        registry.createNode(
            2, 0, CREATOR, MANIFEST_URI, MANIFEST_HASH, TechTreeRegistry.NodeKind.Meta
        );
        assertEq(registry.exists(2), true, "node should be creatable after unpause");
    }

    function testAdminCanGrantAndRevokeWriter() public {
        vm.prank(ADMIN);
        registry.grantWriter(WRITER_TWO);

        vm.prank(WRITER_TWO);
        registry.createNode(
            10, 0, CREATOR, MANIFEST_URI, MANIFEST_HASH, TechTreeRegistry.NodeKind.Skill
        );
        assertEq(registry.exists(10), true, "new writer should be able to create");

        vm.prank(ADMIN);
        registry.revokeWriter(WRITER_TWO);

        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlLite.AccessControlUnauthorizedAccount.selector,
                WRITER_TWO,
                registry.WRITER_ROLE()
            )
        );
        vm.prank(WRITER_TWO);
        registry.createNode(
            11, 0, CREATOR, MANIFEST_URI, MANIFEST_HASH, TechTreeRegistry.NodeKind.Skill
        );
    }

    function testRevertIfNonAdminGrantsWriter() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlLite.AccessControlUnauthorizedAccount.selector,
                OTHER,
                registry.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(OTHER);
        registry.grantWriter(WRITER_TWO);
    }

    function testRevertIfNonAdminPauses() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlLite.AccessControlUnauthorizedAccount.selector,
                OTHER,
                registry.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(OTHER);
        registry.pause();
    }
}
