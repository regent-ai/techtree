// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { StateLibrary } from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import { IV4Router } from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import { Actions } from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import { PathKey } from "@uniswap/v4-periphery/src/libraries/PathKey.sol";

interface ITechUniversalRouter {
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external;
}

interface ITechPermit2Allowance {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

interface ITechAggregatorV3 {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

contract TechExitFeeLotSwap is Ownable {
    using PoolIdLibrary for PoolKey;
    using SafeERC20 for IERC20;

    bytes1 internal constant COMMAND_V4_SWAP = 0x10;

    IERC20 public immutable TECH;
    IERC20 public immutable REGENT;
    address public immutable weth;
    address public vault;
    IPoolManager public immutable poolManager;
    ITechUniversalRouter public immutable universalRouter;
    ITechPermit2Allowance public immutable permit2;
    ITechAggregatorV3 public immutable ethUsdFeed;
    ITechAggregatorV3 public immutable sequencerUptimeFeed;

    PoolKey public techWethPoolKey;
    PoolKey public wethRegentPoolKey;
    bytes32 public immutable techWethPoolId;
    bytes32 public immutable wethRegentPoolId;
    uint128 public minTechWethLiquidity;
    uint128 public minWethRegentLiquidity;
    uint256 public maxEthUsdStalenessSeconds;
    uint256 public sequencerGracePeriodSeconds;

    event ExitSwapExecuted(
        uint256 techAmount, uint256 minRegentOut, address indexed regentRecipient, uint256 regentOut
    );
    event VaultSet(address indexed vault);
    event GuardConfigSet(
        uint128 minTechWethLiquidity,
        uint128 minWethRegentLiquidity,
        uint256 maxEthUsdStalenessSeconds,
        uint256 sequencerGracePeriodSeconds
    );

    error ZeroAddress();
    error AmountZero();
    error MinOutZero();
    error DeadlineExpired();
    error OnlyVault();
    error VaultAlreadySet();
    error AmountTooLarge();
    error PoolIdMismatch();
    error PoolRouteInvalid();
    error PoolUninitialized();
    error PoolLiquidityLow();
    error SequencerDown();
    error SequencerGrace();
    error EthUsdInvalid();
    error EthUsdIncomplete();
    error EthUsdMissing();
    error EthUsdStale();
    error RegentOutLow();
    error InsufficientTech();

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    constructor(
        address owner_,
        address tech_,
        address weth_,
        address regent_,
        address vault_,
        address poolManager_,
        address universalRouter_,
        address permit2_,
        address ethUsdFeed_,
        address sequencerUptimeFeed_,
        PoolKey memory techWethPoolKey_,
        PoolKey memory wethRegentPoolKey_,
        bytes32 techWethPoolId_,
        bytes32 wethRegentPoolId_,
        uint128 minTechWethLiquidity_,
        uint128 minWethRegentLiquidity_,
        uint256 maxEthUsdStalenessSeconds_,
        uint256 sequencerGracePeriodSeconds_
    ) Ownable(owner_) {
        if (
            owner_ == address(0) || tech_ == address(0) || weth_ == address(0)
                || regent_ == address(0) || poolManager_ == address(0)
                || universalRouter_ == address(0) || permit2_ == address(0)
                || ethUsdFeed_ == address(0) || sequencerUptimeFeed_ == address(0)
        ) {
            revert ZeroAddress();
        }
        if (maxEthUsdStalenessSeconds_ == 0) revert AmountZero();
        if (PoolId.unwrap(techWethPoolKey_.toId()) != techWethPoolId_) revert PoolIdMismatch();
        if (PoolId.unwrap(wethRegentPoolKey_.toId()) != wethRegentPoolId_) {
            revert PoolIdMismatch();
        }
        if (!_poolContains(techWethPoolKey_, tech_, weth_)) revert PoolRouteInvalid();
        if (!_poolContains(wethRegentPoolKey_, weth_, regent_)) revert PoolRouteInvalid();

        TECH = IERC20(tech_);
        REGENT = IERC20(regent_);
        weth = weth_;
        vault = vault_;
        poolManager = IPoolManager(poolManager_);
        universalRouter = ITechUniversalRouter(universalRouter_);
        permit2 = ITechPermit2Allowance(permit2_);
        ethUsdFeed = ITechAggregatorV3(ethUsdFeed_);
        sequencerUptimeFeed = ITechAggregatorV3(sequencerUptimeFeed_);
        techWethPoolKey = techWethPoolKey_;
        wethRegentPoolKey = wethRegentPoolKey_;
        techWethPoolId = techWethPoolId_;
        wethRegentPoolId = wethRegentPoolId_;
        _setGuardConfig(
            minTechWethLiquidity_,
            minWethRegentLiquidity_,
            maxEthUsdStalenessSeconds_,
            sequencerGracePeriodSeconds_
        );
        if (vault_ != address(0)) {
            vault = vault_;
            emit VaultSet(vault_);
        }
    }

    function setVault(address vault_) external onlyOwner {
        if (vault_ == address(0)) revert ZeroAddress();
        if (vault != address(0)) revert VaultAlreadySet();
        vault = vault_;
        emit VaultSet(vault_);
    }

    function sellTechForRegent(
        uint256 techAmount,
        uint256 minRegentOut,
        uint256 deadline,
        address regentRecipient
    ) external onlyVault returns (uint256 wethOut, uint256 regentOut) {
        if (techAmount == 0) revert AmountZero();
        if (minRegentOut == 0) revert MinOutZero();
        if (techAmount > type(uint128).max || minRegentOut > type(uint128).max) {
            revert AmountTooLarge();
        }
        if (deadline < block.timestamp) revert DeadlineExpired();
        if (regentRecipient == address(0)) revert ZeroAddress();
        if (TECH.balanceOf(address(this)) < techAmount) revert InsufficientTech();

        _checkOracle();
        _checkPoolLiquidity(techWethPoolKey.toId(), minTechWethLiquidity);
        _checkPoolLiquidity(wethRegentPoolKey.toId(), minWethRegentLiquidity);

        uint256 beforeBalance = REGENT.balanceOf(regentRecipient);
        _approveRouter(techAmount, deadline);
        _executeConfiguredSwap(
            uint128(techAmount), uint128(minRegentOut), deadline, regentRecipient
        );
        regentOut = REGENT.balanceOf(regentRecipient) - beforeBalance;
        if (regentOut < minRegentOut) revert RegentOutLow();

        emit ExitSwapExecuted(techAmount, minRegentOut, regentRecipient, regentOut);
        return (wethOut, regentOut);
    }

    function setGuardConfig(
        uint128 minTechWethLiquidity_,
        uint128 minWethRegentLiquidity_,
        uint256 maxEthUsdStalenessSeconds_,
        uint256 sequencerGracePeriodSeconds_
    ) external onlyOwner {
        _setGuardConfig(
            minTechWethLiquidity_,
            minWethRegentLiquidity_,
            maxEthUsdStalenessSeconds_,
            sequencerGracePeriodSeconds_
        );
    }

    function _setGuardConfig(
        uint128 minTechWethLiquidity_,
        uint128 minWethRegentLiquidity_,
        uint256 maxEthUsdStalenessSeconds_,
        uint256 sequencerGracePeriodSeconds_
    ) internal {
        if (maxEthUsdStalenessSeconds_ == 0) {
            revert AmountZero();
        }
        minTechWethLiquidity = minTechWethLiquidity_;
        minWethRegentLiquidity = minWethRegentLiquidity_;
        maxEthUsdStalenessSeconds = maxEthUsdStalenessSeconds_;
        sequencerGracePeriodSeconds = sequencerGracePeriodSeconds_;
        emit GuardConfigSet(
            minTechWethLiquidity_,
            minWethRegentLiquidity_,
            maxEthUsdStalenessSeconds_,
            sequencerGracePeriodSeconds_
        );
    }

    function _approveRouter(uint256 techAmount, uint256 deadline) internal {
        TECH.forceApprove(address(permit2), techAmount);
        permit2.approve(
            address(TECH), address(universalRouter), uint160(techAmount), uint48(deadline)
        );
    }

    function _executeConfiguredSwap(
        uint128 techAmount,
        uint128 minRegentOut,
        uint256 deadline,
        address recipient
    ) internal {
        PathKey[] memory path = new PathKey[](2);
        path[0] = PathKey({
            intermediateCurrency: Currency.wrap(weth),
            fee: techWethPoolKey.fee,
            tickSpacing: techWethPoolKey.tickSpacing,
            hooks: techWethPoolKey.hooks,
            hookData: bytes("")
        });
        path[1] = PathKey({
            intermediateCurrency: Currency.wrap(address(REGENT)),
            fee: wethRegentPoolKey.fee,
            tickSpacing: wethRegentPoolKey.tickSpacing,
            hooks: wethRegentPoolKey.hooks,
            hookData: bytes("")
        });

        uint256[] memory minHopPriceX36 = new uint256[](0);
        IV4Router.ExactInputParams memory exactInput = IV4Router.ExactInputParams({
            currencyIn: Currency.wrap(address(TECH)),
            path: path,
            minHopPriceX36: minHopPriceX36,
            amountIn: techAmount,
            amountOutMinimum: minRegentOut
        });

        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL)
        );
        bytes[] memory actionParams = new bytes[](3);
        actionParams[0] = abi.encode(exactInput);
        actionParams[1] = abi.encode(Currency.wrap(address(TECH)), uint256(techAmount));
        actionParams[2] =
            abi.encode(Currency.wrap(address(REGENT)), recipient, uint256(minRegentOut));

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, actionParams);

        bytes memory commands = abi.encodePacked(COMMAND_V4_SWAP);
        universalRouter.execute(commands, inputs, deadline);
    }

    function _checkOracle() internal view {
        (, int256 sequencerAnswer, uint256 sequencerStartedAt,,) =
            sequencerUptimeFeed.latestRoundData();
        if (sequencerAnswer != 0) revert SequencerDown();
        if (block.timestamp < sequencerStartedAt + sequencerGracePeriodSeconds) {
            revert SequencerGrace();
        }

        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) =
            ethUsdFeed.latestRoundData();
        if (answer <= 0) revert EthUsdInvalid();
        if (answeredInRound < roundId) revert EthUsdIncomplete();
        if (updatedAt == 0) revert EthUsdMissing();
        if (updatedAt + maxEthUsdStalenessSeconds < block.timestamp) revert EthUsdStale();
    }

    function _checkPoolLiquidity(PoolId poolId, uint128 minimumLiquidity) internal view {
        (uint160 sqrtPriceX96,,,) = StateLibrary.getSlot0(poolManager, poolId);
        if (sqrtPriceX96 == 0) revert PoolUninitialized();

        uint128 liquidity = StateLibrary.getLiquidity(poolManager, poolId);
        if (liquidity < minimumLiquidity) revert PoolLiquidityLow();
    }

    function _poolContains(PoolKey memory poolKey, address tokenA, address tokenB)
        internal
        pure
        returns (bool)
    {
        address currency0 = Currency.unwrap(poolKey.currency0);
        address currency1 = Currency.unwrap(poolKey.currency1);
        return (currency0 == tokenA && currency1 == tokenB)
            || (currency0 == tokenB && currency1 == tokenA);
    }
}
