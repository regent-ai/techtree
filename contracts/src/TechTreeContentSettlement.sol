// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Base-first USDC settlement rail for paid TechTree content.
/// @dev Keeps listing policy offchain and only records the payment split onchain.
contract TechTreeContentSettlement {
    using SafeERC20 for IERC20;

    uint16 public constant TREASURY_BPS = 100;
    uint16 public constant SELLER_BPS = 9900;

    IERC20 public immutable usdcToken;
    address public immutable treasury;

    error ZeroAddress();
    error ZeroAmount();
    error ZeroListingRef();

    event PurchaseSettled(
        bytes32 indexed listingRef,
        address indexed buyer,
        address indexed seller,
        bytes32 bundleRef,
        uint256 amount,
        uint256 treasuryAmount,
        uint256 sellerAmount
    );

    constructor(address usdcToken_, address treasury_) {
        if (usdcToken_ == address(0) || treasury_ == address(0)) {
            revert ZeroAddress();
        }

        usdcToken = IERC20(usdcToken_);
        treasury = treasury_;
    }

    function settlePurchase(bytes32 listingRef, address seller, bytes32 bundleRef, uint256 amount)
        external
    {
        if (listingRef == bytes32(0)) revert ZeroListingRef();
        if (seller == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        uint256 treasuryAmount = amount / 100;
        uint256 sellerAmount = amount - treasuryAmount;

        usdcToken.safeTransferFrom(msg.sender, treasury, treasuryAmount);
        usdcToken.safeTransferFrom(msg.sender, seller, sellerAmount);

        emit PurchaseSettled(
            listingRef, msg.sender, seller, bundleRef, amount, treasuryAmount, sellerAmount
        );
    }
}
