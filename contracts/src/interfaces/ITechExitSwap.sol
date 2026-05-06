// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface ITechExitSwap {
    function sellTechForRegent(
        uint256 techAmount,
        uint256 minRegentOut,
        uint256 deadline,
        address regentRecipient
    ) external returns (uint256 wethOut, uint256 regentOut);
}
