// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { TechTreeContentSettlement } from "../src/TechTreeContentSettlement.sol";
import { TestBase } from "./utils/TestBase.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") { }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract TechTreeContentSettlementTest is TestBase {
    MockUSDC internal usdc;
    TechTreeContentSettlement internal settlement;

    address internal constant BUYER = address(0xB0B);
    address internal constant SELLER = address(0x5E11E);
    address internal constant TREASURY = address(0x7EA5A);
    bytes32 internal constant LISTING_REF = keccak256("listing-1");
    bytes32 internal constant BUNDLE_REF = keccak256("bundle-1");

    function setUp() public {
        usdc = new MockUSDC();
        settlement = new TechTreeContentSettlement(address(usdc), TREASURY);

        usdc.mint(BUYER, 1_000_000_000);

        vm.prank(BUYER);
        usdc.approve(address(settlement), type(uint256).max);
    }

    function testStoresImmutableConfig() public view {
        assertEq(address(settlement.usdcToken()), address(usdc), "usdc token mismatch");
        assertEq(settlement.treasury(), TREASURY, "treasury mismatch");
        assertEq(settlement.TREASURY_BPS(), 100, "treasury bps mismatch");
        assertEq(settlement.SELLER_BPS(), 9900, "seller bps mismatch");
    }

    function testSettlesUsdcSplitAndEmitsEvent() public {
        uint256 amount = 125_678_901;
        uint256 expectedTreasury = amount / 100;
        uint256 expectedSeller = amount - expectedTreasury;

        recordLogs();

        vm.prank(BUYER);
        settlement.settlePurchase(LISTING_REF, SELLER, BUNDLE_REF, amount);

        (bytes32[] memory topics, bytes memory data, address emitter, uint256 totalLogs) =
            readRecordedLog(2);

        assertEq(totalLogs, 3, "expected transfer + transfer + settlement logs");
        assertEq(emitter, address(settlement), "settlement emitter mismatch");
        assertEq(
            topics[0],
            keccak256("PurchaseSettled(bytes32,address,address,bytes32,uint256,uint256,uint256)"),
            "settlement topic mismatch"
        );
        assertEq(topics[1], LISTING_REF, "listing ref mismatch");
        assertEq(topics[2], bytes32(uint256(uint160(BUYER))), "buyer topic mismatch");
        assertEq(topics[3], bytes32(uint256(uint160(SELLER))), "seller topic mismatch");

        (bytes32 bundleRef, uint256 settledAmount, uint256 treasuryAmount, uint256 sellerAmount) =
            abi.decode(data, (bytes32, uint256, uint256, uint256));

        assertEq(bundleRef, BUNDLE_REF, "bundle ref mismatch");
        assertEq(settledAmount, amount, "settled amount mismatch");
        assertEq(treasuryAmount, expectedTreasury, "treasury event mismatch");
        assertEq(sellerAmount, expectedSeller, "seller event mismatch");

        assertEq(usdc.balanceOf(TREASURY), expectedTreasury, "treasury payout mismatch");
        assertEq(usdc.balanceOf(SELLER), expectedSeller, "seller payout mismatch");
        assertEq(usdc.balanceOf(BUYER), 1_000_000_000 - amount, "buyer balance mismatch");
    }

    function testSellerGetsRemainderFromRounding() public {
        vm.prank(BUYER);
        settlement.settlePurchase(LISTING_REF, SELLER, BUNDLE_REF, 101);

        assertEq(usdc.balanceOf(TREASURY), 1, "treasury should round down");
        assertEq(usdc.balanceOf(SELLER), 100, "seller should receive remainder");
    }

    function testRevertIfConstructorUsesZeroAddresses() public {
        vm.expectRevert(TechTreeContentSettlement.ZeroAddress.selector);
        new TechTreeContentSettlement(address(0), TREASURY);

        vm.expectRevert(TechTreeContentSettlement.ZeroAddress.selector);
        new TechTreeContentSettlement(address(usdc), address(0));
    }

    function testRevertIfListingRefIsZero() public {
        vm.expectRevert(TechTreeContentSettlement.ZeroListingRef.selector);
        vm.prank(BUYER);
        settlement.settlePurchase(bytes32(0), SELLER, BUNDLE_REF, 1);
    }

    function testRevertIfSellerIsZero() public {
        vm.expectRevert(TechTreeContentSettlement.ZeroAddress.selector);
        vm.prank(BUYER);
        settlement.settlePurchase(LISTING_REF, address(0), BUNDLE_REF, 1);
    }

    function testRevertIfAmountIsZero() public {
        vm.expectRevert(TechTreeContentSettlement.ZeroAmount.selector);
        vm.prank(BUYER);
        settlement.settlePurchase(LISTING_REF, SELLER, BUNDLE_REF, 0);
    }
}
