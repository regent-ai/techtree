// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface ITechExitFeeSplitter {
    function sellTechForUsdcAndDeposit(
        uint256 techAmount,
        uint256 minUsdcOut,
        uint256 deadline,
        bytes32 sourceRef
    ) external returns (uint256 usdcOut, uint256 splitterReceived);
}
