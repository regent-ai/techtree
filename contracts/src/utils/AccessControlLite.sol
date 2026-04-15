// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal access control with OpenZeppelin-compatible role semantics.
abstract contract AccessControlLite {
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    mapping(bytes32 role => mapping(address account => bool hasRole_)) private _roles;

    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    modifier onlyRole(bytes32 role) {
        _checkRole(role);
        _;
    }

    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role][account];
    }

    function grantRole(bytes32 role, address account) public virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) public virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(role, account);
    }

    function _checkRole(bytes32 role) internal view {
        if (!_roles[role][msg.sender]) {
            revert AccessControlUnauthorizedAccount(msg.sender, role);
        }
    }

    function _grantRole(bytes32 role, address account) internal {
        if (_roles[role][account]) return;
        _roles[role][account] = true;
        emit RoleGranted(role, account, msg.sender);
    }

    function _revokeRole(bytes32 role, address account) internal {
        if (!_roles[role][account]) return;
        _roles[role][account] = false;
        emit RoleRevoked(role, account, msg.sender);
    }
}

