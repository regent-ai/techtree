// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";

import { TechToken } from "../../src/TechToken.sol";

contract TechTokenTest is Test {
    address internal constant ADMIN = address(0xA11CE);
    address internal constant ALICE = address(0xA11CE1);
    address internal constant MINTER = address(0xBEEF);

    TechToken internal tech;

    function setUp() public {
        tech = new TechToken(ADMIN, 100 ether);
    }

    function testOnlyMinterCanMint() public {
        vm.expectRevert();
        tech.mint(ALICE, 1 ether);

        vm.prank(ADMIN);
        tech.mint(ALICE, 1 ether);
        assertEq(tech.balanceOf(ALICE), 1 ether);
    }

    function testAdminCanGrantAndRevokeMinterRole() public {
        bytes32 minterRole = tech.MINTER_ROLE();

        vm.startPrank(ADMIN);
        tech.grantRole(minterRole, MINTER);
        vm.stopPrank();

        vm.prank(MINTER);
        tech.mint(ALICE, 5 ether);
        assertEq(tech.balanceOf(ALICE), 5 ether);

        vm.prank(ADMIN);
        tech.revokeRole(minterRole, MINTER);

        vm.prank(MINTER);
        vm.expectRevert();
        tech.mint(ALICE, 1 ether);
    }

    function testMintRejectsOverMaxSupply() public {
        vm.prank(ADMIN);
        tech.mint(ALICE, 100 ether);

        vm.prank(ADMIN);
        vm.expectRevert(TechToken.MaxSupplyExceeded.selector);
        tech.mint(ALICE, 1);
    }

    function testConstructorRejectsBadInputs() public {
        vm.expectRevert(TechToken.AdminZero.selector);
        new TechToken(address(0), 100 ether);

        vm.expectRevert(TechToken.MaxSupplyZero.selector);
        new TechToken(ADMIN, 0);
    }
}
