// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library TestPreference {
    function boundPreference(uint256 raw, uint256 wad) internal pure returns (uint256) {
        if (raw % 5 == 0) return 0;
        if (raw % 5 == 1) return 1;
        if (raw % 5 == 2) return wad - 1;
        if (raw % 5 == 3) return wad / 2;
        return raw % (wad + 1);
    }
}
