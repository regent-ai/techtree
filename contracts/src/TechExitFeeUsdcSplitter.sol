// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
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

interface ITechRegentRevenueStaking {
    function usdc() external view returns (address);

    function depositUSDC(uint256 amount, bytes32 sourceTag, bytes32 sourceRef)
        external
        returns (uint256 received);
}

contract TechExitFeeUsdcSplitter is Ownable, ReentrancyGuard {
    using PoolIdLibrary for PoolKey;
    using SafeERC20 for IERC20;

    bytes1 internal constant COMMAND_V4_SWAP = 0x10;
    bytes32 public constant SOURCE_TAG = keccak256("techtree.tech.exit_fee.v0.2");

    IERC20 public immutable TECH;
    IERC20 public immutable USDC;
    address public immutable weth;
    address public vault;
    IPoolManager public immutable poolManager;
    ITechUniversalRouter public immutable universalRouter;
    ITechPermit2Allowance public immutable permit2;
    ITechAggregatorV3 public immutable ethUsdFeed;
    ITechAggregatorV3 public immutable sequencerUptimeFeed;
    ITechRegentRevenueStaking public immutable regentRevenueStaking;

    PoolKey public techWethPoolKey;
    PoolKey public wethUsdcPoolKey;
    bytes32 public immutable techWethPoolId;
    bytes32 public immutable wethUsdcPoolId;
    uint128 public minTechWethLiquidity;
    uint128 public minWethUsdcLiquidity;
    uint256 public maxEthUsdStalenessSeconds;
    uint256 public sequencerGracePeriodSeconds;

    struct Addresses {
        address owner;
        address tech;
        address weth;
        address usdc;
        address vault;
        address poolManager;
        address universalRouter;
        address permit2;
        address ethUsdFeed;
        address sequencerUptimeFeed;
        address regentRevenueStaking;
    }

    struct Pools {
        PoolKey techWethPoolKey;
        PoolKey wethUsdcPoolKey;
        bytes32 techWethPoolId;
        bytes32 wethUsdcPoolId;
        uint128 minTechWethLiquidity;
        uint128 minWethUsdcLiquidity;
    }

    struct Guards {
        uint256 maxEthUsdStalenessSeconds;
        uint256 sequencerGracePeriodSeconds;
    }

    event ExitFeeDeposited(
        uint256 techAmount,
        uint256 minUsdcOut,
        address indexed regentRevenueStaking,
        uint256 usdcOut,
        uint256 splitterReceived,
        bytes32 indexed sourceRef
    );
    event VaultSet(address indexed vault);
    event GuardConfigSet(
        uint128 minTechWethLiquidity,
        uint128 minWethUsdcLiquidity,
        uint256 maxEthUsdStalenessSeconds,
        uint256 sequencerGracePeriodSeconds
    );

    error ZeroAddress();
    error AmountZero();
    error MinOutZero();
    error SourceRefZero();
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
    error UsdcOutLow();
    error InsufficientTech();
    error StakingUsdcMismatch();
    error SplitterReceivedMismatch();

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    constructor(Addresses memory addresses, Pools memory pools, Guards memory guards)
        Ownable(addresses.owner)
    {
        if (
            addresses.owner == address(0) || addresses.tech == address(0)
                || addresses.weth == address(0) || addresses.usdc == address(0)
                || addresses.poolManager == address(0) || addresses.universalRouter == address(0)
                || addresses.permit2 == address(0) || addresses.ethUsdFeed == address(0)
                || addresses.sequencerUptimeFeed == address(0)
                || addresses.regentRevenueStaking == address(0)
        ) {
            revert ZeroAddress();
        }
        if (guards.maxEthUsdStalenessSeconds == 0) revert AmountZero();
        if (PoolId.unwrap(pools.techWethPoolKey.toId()) != pools.techWethPoolId) {
            revert PoolIdMismatch();
        }
        if (PoolId.unwrap(pools.wethUsdcPoolKey.toId()) != pools.wethUsdcPoolId) {
            revert PoolIdMismatch();
        }
        if (!_poolContains(pools.techWethPoolKey, addresses.tech, addresses.weth)) {
            revert PoolRouteInvalid();
        }
        if (!_poolContains(pools.wethUsdcPoolKey, addresses.weth, addresses.usdc)) {
            revert PoolRouteInvalid();
        }
        if (ITechRegentRevenueStaking(addresses.regentRevenueStaking).usdc() != addresses.usdc) {
            revert StakingUsdcMismatch();
        }

        TECH = IERC20(addresses.tech);
        USDC = IERC20(addresses.usdc);
        weth = addresses.weth;
        vault = addresses.vault;
        poolManager = IPoolManager(addresses.poolManager);
        universalRouter = ITechUniversalRouter(addresses.universalRouter);
        permit2 = ITechPermit2Allowance(addresses.permit2);
        ethUsdFeed = ITechAggregatorV3(addresses.ethUsdFeed);
        sequencerUptimeFeed = ITechAggregatorV3(addresses.sequencerUptimeFeed);
        regentRevenueStaking = ITechRegentRevenueStaking(addresses.regentRevenueStaking);
        techWethPoolKey = pools.techWethPoolKey;
        wethUsdcPoolKey = pools.wethUsdcPoolKey;
        techWethPoolId = pools.techWethPoolId;
        wethUsdcPoolId = pools.wethUsdcPoolId;
        _setGuardConfig(
            pools.minTechWethLiquidity,
            pools.minWethUsdcLiquidity,
            guards.maxEthUsdStalenessSeconds,
            guards.sequencerGracePeriodSeconds
        );
        if (addresses.vault != address(0)) {
            vault = addresses.vault;
            emit VaultSet(addresses.vault);
        }
    }

    function setVault(address vault_) external onlyOwner {
        if (vault_ == address(0)) revert ZeroAddress();
        if (vault != address(0)) revert VaultAlreadySet();
        vault = vault_;
        emit VaultSet(vault_);
    }

    function sellTechForUsdcAndDeposit(
        uint256 techAmount,
        uint256 minUsdcOut,
        uint256 deadline,
        bytes32 sourceRef
    ) external onlyVault nonReentrant returns (uint256 usdcOut, uint256 splitterReceived) {
        if (techAmount == 0) revert AmountZero();
        if (minUsdcOut == 0) revert MinOutZero();
        if (sourceRef == bytes32(0)) revert SourceRefZero();
        if (techAmount > type(uint128).max || minUsdcOut > type(uint128).max) {
            revert AmountTooLarge();
        }
        if (deadline > type(uint48).max) revert AmountTooLarge();
        if (deadline < block.timestamp) revert DeadlineExpired();
        if (TECH.balanceOf(address(this)) < techAmount) revert InsufficientTech();

        _checkOracle();
        _checkPoolLiquidity(techWethPoolKey.toId(), minTechWethLiquidity);
        _checkPoolLiquidity(wethUsdcPoolKey.toId(), minWethUsdcLiquidity);

        uint256 beforeBalance = USDC.balanceOf(address(this));
        _approveRouter(techAmount, deadline);
        _executeConfiguredSwap(uint128(techAmount), uint128(minUsdcOut), deadline, address(this));
        usdcOut = USDC.balanceOf(address(this)) - beforeBalance;
        if (usdcOut < minUsdcOut) revert UsdcOutLow();

        USDC.forceApprove(address(regentRevenueStaking), usdcOut);
        splitterReceived = regentRevenueStaking.depositUSDC(usdcOut, SOURCE_TAG, sourceRef);
        if (splitterReceived != usdcOut) revert SplitterReceivedMismatch();
        USDC.forceApprove(address(regentRevenueStaking), 0);

        emit ExitFeeDeposited(
            techAmount,
            minUsdcOut,
            address(regentRevenueStaking),
            usdcOut,
            splitterReceived,
            sourceRef
        );
    }

    function setGuardConfig(
        uint128 minTechWethLiquidity_,
        uint128 minWethUsdcLiquidity_,
        uint256 maxEthUsdStalenessSeconds_,
        uint256 sequencerGracePeriodSeconds_
    ) external onlyOwner {
        _setGuardConfig(
            minTechWethLiquidity_,
            minWethUsdcLiquidity_,
            maxEthUsdStalenessSeconds_,
            sequencerGracePeriodSeconds_
        );
    }

    function _setGuardConfig(
        uint128 minTechWethLiquidity_,
        uint128 minWethUsdcLiquidity_,
        uint256 maxEthUsdStalenessSeconds_,
        uint256 sequencerGracePeriodSeconds_
    ) internal {
        if (maxEthUsdStalenessSeconds_ == 0) {
            revert AmountZero();
        }
        minTechWethLiquidity = minTechWethLiquidity_;
        minWethUsdcLiquidity = minWethUsdcLiquidity_;
        maxEthUsdStalenessSeconds = maxEthUsdStalenessSeconds_;
        sequencerGracePeriodSeconds = sequencerGracePeriodSeconds_;
        emit GuardConfigSet(
            minTechWethLiquidity_,
            minWethUsdcLiquidity_,
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
        uint128 minUsdcOut,
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
            intermediateCurrency: Currency.wrap(address(USDC)),
            fee: wethUsdcPoolKey.fee,
            tickSpacing: wethUsdcPoolKey.tickSpacing,
            hooks: wethUsdcPoolKey.hooks,
            hookData: bytes("")
        });

        uint256[] memory minHopPriceX36 = new uint256[](0);
        IV4Router.ExactInputParams memory exactInput = IV4Router.ExactInputParams({
            currencyIn: Currency.wrap(address(TECH)),
            path: path,
            minHopPriceX36: minHopPriceX36,
            amountIn: techAmount,
            amountOutMinimum: minUsdcOut
        });

        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL)
        );
        bytes[] memory actionParams = new bytes[](3);
        actionParams[0] = abi.encode(exactInput);
        actionParams[1] = abi.encode(Currency.wrap(address(TECH)), uint256(techAmount));
        actionParams[2] = abi.encode(Currency.wrap(address(USDC)), recipient, uint256(minUsdcOut));

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
