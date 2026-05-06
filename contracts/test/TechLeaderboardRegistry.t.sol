// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";

import { TechLeaderboardRegistry } from "../src/TechLeaderboardRegistry.sol";

contract TechLeaderboardRegistryTest is Test {
    address internal constant ADMIN = address(0xA11CE);
    address internal constant OTHER = address(0xB0B);
    bytes32 internal constant BOARD_ID = keccak256("bbh.default.v1");
    bytes32 internal constant CONFIG_HASH = keccak256("config");

    TechLeaderboardRegistry internal registry;

    function setUp() public {
        registry = new TechLeaderboardRegistry(ADMIN);
    }

    function testManagerCanRegisterUpdateAndDeactivate() public {
        vm.prank(ADMIN);
        registry.registerLeaderboard(
            TechLeaderboardRegistry.Leaderboard({
                id: BOARD_ID,
                kind: 1,
                weightBps: 5_000,
                startsEpoch: 0,
                endsEpoch: 0,
                configHash: CONFIG_HASH,
                uri: "ipfs://board",
                active: true
            })
        );

        TechLeaderboardRegistry.Leaderboard memory board = registry.getLeaderboard(BOARD_ID);
        assertEq(board.weightBps, 5_000);
        assertTrue(board.active);

        vm.prank(ADMIN);
        registry.updateLeaderboard(BOARD_ID, 4_000, keccak256("next"), "ipfs://next");
        board = registry.getLeaderboard(BOARD_ID);
        assertEq(board.weightBps, 4_000);

        vm.prank(ADMIN);
        registry.setLeaderboardActive(BOARD_ID, false);
        board = registry.getLeaderboard(BOARD_ID);
        assertFalse(board.active);
    }

    function testNonManagerCannotRegister() public {
        vm.prank(OTHER);
        vm.expectRevert();
        registry.registerLeaderboard(
            TechLeaderboardRegistry.Leaderboard({
                id: BOARD_ID,
                kind: 1,
                weightBps: 5_000,
                startsEpoch: 0,
                endsEpoch: 0,
                configHash: CONFIG_HASH,
                uri: "ipfs://board",
                active: true
            })
        );
    }

    function testRejectsDuplicateAndInvalidWeight() public {
        vm.startPrank(ADMIN);
        registry.registerLeaderboard(
            TechLeaderboardRegistry.Leaderboard({
                id: BOARD_ID,
                kind: 1,
                weightBps: 5_000,
                startsEpoch: 0,
                endsEpoch: 0,
                configHash: CONFIG_HASH,
                uri: "ipfs://board",
                active: true
            })
        );

        vm.expectRevert(TechLeaderboardRegistry.DuplicateLeaderboard.selector);
        registry.registerLeaderboard(
            TechLeaderboardRegistry.Leaderboard({
                id: BOARD_ID,
                kind: 1,
                weightBps: 5_000,
                startsEpoch: 0,
                endsEpoch: 0,
                configHash: CONFIG_HASH,
                uri: "ipfs://board",
                active: true
            })
        );

        vm.expectRevert(TechLeaderboardRegistry.WeightTooHigh.selector);
        registry.updateLeaderboard(BOARD_ID, 10_001, CONFIG_HASH, "ipfs://board");
        vm.stopPrank();
    }
}
