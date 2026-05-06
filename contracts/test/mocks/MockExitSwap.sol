// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { ITechExitSwap } from "../../src/interfaces/ITechExitSwap.sol";

contract MockExitSwap is ITechExitSwap {
    uint256 public lastTechAmount;
    uint256 public lastMinRegentOut;
    uint256 public lastDeadline;
    address public lastRegentRecipient;
    uint256 public nextRegentOut = 1 ether;
    bool public shouldRevert;

    function setNextRegentOut(uint256 nextRegentOut_) external {
        nextRegentOut = nextRegentOut_;
    }

    function setShouldRevert(bool shouldRevert_) external {
        shouldRevert = shouldRevert_;
    }

    function sellTechForRegent(
        uint256 techAmount,
        uint256 minRegentOut,
        uint256 deadline,
        address regentRecipient
    ) external returns (uint256 wethOut, uint256 regentOut) {
        require(!shouldRevert, "SWAP_FAILED");
        lastTechAmount = techAmount;
        lastMinRegentOut = minRegentOut;
        lastDeadline = deadline;
        lastRegentRecipient = regentRecipient;
        return (wethOut, nextRegentOut);
    }
}
