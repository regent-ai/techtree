// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

contract TechToken is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint256 public immutable maxSupply;

    error AdminZero();
    error MaxSupplyZero();
    error ToZero();
    error MaxSupplyExceeded();

    constructor(address admin, uint256 maxSupply_) ERC20("Tech", "TECH") {
        if (admin == address(0)) revert AdminZero();
        if (maxSupply_ == 0) revert MaxSupplyZero();

        maxSupply = maxSupply_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (to == address(0)) revert ToZero();
        if (totalSupply() + amount > maxSupply) revert MaxSupplyExceeded();
        _mint(to, amount);
    }
}
