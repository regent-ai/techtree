// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

library TechEpochMath {
    function nextEmission(uint256 currentEmission, uint256 decayNumerator, uint256 decayDenominator)
        internal
        pure
        returns (uint256)
    {
        uint256 next = Math.mulDiv(currentEmission, decayNumerator, decayDenominator);

        if (currentEmission > 1 && next >= currentEmission) {
            return currentEmission - 1;
        }

        return next;
    }
}
