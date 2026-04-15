// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface Vm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function prank(address msgSender) external;
    function startPrank(address msgSender) external;
    function stopPrank() external;
    function expectRevert(bytes calldata revertData) external;
    function expectRevert(bytes4 revertData) external;
    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory);
}

contract TestBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    error AssertionFailed(string message);

    function recordLogs() internal {
        vm.recordLogs();
    }

    function readRecordedLog(uint256 index)
        internal
        returns (bytes32[] memory topics, bytes memory data, address emitter, uint256 totalLogs)
    {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        totalLogs = logs.length;
        if (index >= totalLogs) revert AssertionFailed("recorded log index out of bounds");

        Vm.Log memory selected = logs[index];
        return (selected.topics, selected.data, selected.emitter, totalLogs);
    }

    function assertTrue(bool condition, string memory message) internal pure {
        if (!condition) revert AssertionFailed(message);
    }

    function assertEq(uint256 actual, uint256 expected, string memory message) internal pure {
        if (actual != expected) revert AssertionFailed(message);
    }

    function assertEq(address actual, address expected, string memory message) internal pure {
        if (actual != expected) revert AssertionFailed(message);
    }

    function assertEq(bytes32 actual, bytes32 expected, string memory message) internal pure {
        if (actual != expected) revert AssertionFailed(message);
    }

    function assertEq(bool actual, bool expected, string memory message) internal pure {
        if (actual != expected) revert AssertionFailed(message);
    }

    function assertEq(string memory actual, string memory expected, string memory message)
        internal
        pure
    {
        if (keccak256(bytes(actual)) != keccak256(bytes(expected))) {
            revert AssertionFailed(message);
        }
    }
}
