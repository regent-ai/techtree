// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal pausable primitive with OpenZeppelin-compatible error names.
abstract contract PausableLite {
    bool private _paused;

    error EnforcedPause();
    error ExpectedPause();

    event Paused(address indexed account);
    event Unpaused(address indexed account);

    modifier whenNotPaused() {
        if (_paused) revert EnforcedPause();
        _;
    }

    function paused() public view returns (bool) {
        return _paused;
    }

    function _pause() internal {
        if (_paused) revert EnforcedPause();
        _paused = true;
        emit Paused(msg.sender);
    }

    function _unpause() internal {
        if (!_paused) revert ExpectedPause();
        _paused = false;
        emit Unpaused(msg.sender);
    }
}
