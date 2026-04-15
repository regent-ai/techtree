// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { TechToken } from "../../src/TechToken.sol";
import { TechContractsBase } from "../utils/TechContractsBase.sol";

contract TechTokenTest is TechContractsBase {
    address internal constant MINTER = address(0x1111);

    function setUp() public {
        _deployToken();
    }

    function test_onlyMinterCanMint() public {
        vm.expectRevert();
        tech.mint(ALICE, 1 ether);

        _mintTech(ALICE, 1 ether);
        assertEq(tech.balanceOf(ALICE), 1 ether);
    }

    function test_adminCanGrantMinterRole() public {
        _grantMinterRole(MINTER);

        vm.prank(MINTER);
        tech.mint(ALICE, 5 ether);

        assertEq(tech.balanceOf(ALICE), 5 ether);
    }

    function test_adminCanRevokeMinterRole() public {
        bytes32 minterRole = tech.MINTER_ROLE();
        _grantMinterRole(MINTER);

        vm.prank(ADMIN);
        tech.revokeRole(minterRole, MINTER);

        vm.prank(MINTER);
        vm.expectRevert();
        tech.mint(ALICE, 1 ether);
    }

    function test_constructorRejectsZeroAdmin() public {
        vm.expectRevert(bytes("admin=0"));
        new TechToken(address(0));
    }
}
