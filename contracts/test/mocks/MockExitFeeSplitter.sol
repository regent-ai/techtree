// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { ITechExitFeeSplitter } from "../../src/interfaces/ITechExitFeeSplitter.sol";

contract MockExitFeeSplitter is ITechExitFeeSplitter {
    uint256 public lastTechAmount;
    uint256 public lastMinUsdcOut;
    uint256 public lastDeadline;
    bytes32 public lastSourceRef;
    uint256 public nextUsdcOut = 1 ether;
    uint256 public nextSplitterReceived = 1 ether;
    bool public shouldRevert;

    function setNextUsdcOut(uint256 nextUsdcOut_) external {
        nextUsdcOut = nextUsdcOut_;
    }

    function setNextSplitterReceived(uint256 nextSplitterReceived_) external {
        nextSplitterReceived = nextSplitterReceived_;
    }

    function setShouldRevert(bool shouldRevert_) external {
        shouldRevert = shouldRevert_;
    }

    function sellTechForUsdcAndDeposit(
        uint256 techAmount,
        uint256 minUsdcOut,
        uint256 deadline,
        bytes32 sourceRef
    ) external returns (uint256 usdcOut, uint256 splitterReceived) {
        require(!shouldRevert, "SPLITTER_FAILED");
        lastTechAmount = techAmount;
        lastMinUsdcOut = minUsdcOut;
        lastDeadline = deadline;
        lastSourceRef = sourceRef;
        return (nextUsdcOut, nextSplitterReceived);
    }
}
