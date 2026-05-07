// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Script, console2 } from "forge-std/Script.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";

import { TechAgentRewardVault } from "../src/TechAgentRewardVault.sol";
import { TechEmissionControllerV2 } from "../src/TechEmissionControllerV2.sol";
import { TechExitFeeUsdcSplitter } from "../src/TechExitFeeUsdcSplitter.sol";
import { TechLeaderboardRegistry } from "../src/TechLeaderboardRegistry.sol";
import { TechRewardRouter } from "../src/TechRewardRouter.sol";
import { TechToken } from "../src/TechToken.sol";

/// @notice Deploys the TECH v0.2 stack for anvil, Base Sepolia, or Base mainnet.
contract DeployTechStack is Script {
    using PoolIdLibrary for PoolKey;

    bytes32 internal constant ANVIL_TARGET_HASH = keccak256(bytes("anvil"));
    bytes32 internal constant BASE_SEPOLIA_TARGET_HASH = keccak256(bytes("base-sepolia"));
    bytes32 internal constant BASE_MAINNET_TARGET_HASH = keccak256(bytes("base-mainnet"));
    uint256 internal constant ANVIL_CHAIN_ID = 31_337;
    uint256 internal constant BASE_SEPOLIA_CHAIN_ID = 84_532;
    uint256 internal constant BASE_MAINNET_CHAIN_ID = 8_453;

    struct DeployConfig {
        address admin;
        address owner;
        address rootManager;
        address leaderboardManager;
        address pauser;
        address agentRegistry;
        address weth;
        address usdc;
        address regentRevenueStaking;
        address poolManager;
        address universalRouter;
        address permit2;
        address ethUsdFeed;
        address sequencerUptimeFeed;
        uint256 maxSupply;
        uint64 epochDuration;
        uint64 maxEpochs;
        uint256 initialEpochEmission;
        uint256 maxEmissionSupply;
        uint256 decayNumerator;
        uint256 decayDenominator;
        uint24 techWethPoolFee;
        int24 techWethTickSpacing;
        address techWethHooks;
        uint24 wethUsdcPoolFee;
        int24 wethUsdcTickSpacing;
        address wethUsdcHooks;
        uint128 minTechWethLiquidity;
        uint128 minWethUsdcLiquidity;
        uint256 maxEthUsdStalenessSeconds;
        uint256 sequencerGracePeriodSeconds;
    }

    struct DeployedContracts {
        TechToken tech;
        TechExitFeeUsdcSplitter exitFeeSplitter;
        TechAgentRewardVault vault;
        TechRewardRouter router;
        TechEmissionControllerV2 controller;
        TechLeaderboardRegistry leaderboardRegistry;
    }

    error InvalidDeployTarget(string target);
    error UnexpectedChainId(uint256 expected, uint256 actual);
    error ZeroAddressConfig(string key);
    error UintTooLarge(string key);

    function run() external returns (DeployedContracts memory deployed) {
        string memory target = vm.envOr("DEPLOY_TARGET", string("base-mainnet"));
        deployed = _runTarget(target);
    }

    function runAnvil() external returns (DeployedContracts memory deployed) {
        deployed = _runTarget("anvil");
    }

    function runBaseSepolia() external returns (DeployedContracts memory deployed) {
        deployed = _runTarget("base-sepolia");
    }

    function runBaseMainnet() external returns (DeployedContracts memory deployed) {
        deployed = _runTarget("base-mainnet");
    }

    function _runTarget(string memory target) internal returns (DeployedContracts memory deployed) {
        _checkChainId(target);
        uint256 deployerKey = _privateKeyForTarget(target);
        address deployer = vm.addr(deployerKey);
        DeployConfig memory config = _deployConfig();

        vm.startBroadcast(deployerKey);
        deployed = _deploy(config, deployer);
        _wireRoles(deployed, config, deployer);
        vm.stopBroadcast();

        console2.log(_resultJson(deployed));
    }

    function _deploy(DeployConfig memory config, address deployer)
        internal
        returns (DeployedContracts memory deployed)
    {
        deployed.tech = new TechToken(deployer, config.maxSupply);

        PoolKey memory techWethPoolKey = _sortedPoolKey(
            address(deployed.tech),
            config.weth,
            config.techWethPoolFee,
            config.techWethTickSpacing,
            config.techWethHooks
        );
        PoolKey memory wethUsdcPoolKey = _sortedPoolKey(
            config.weth,
            config.usdc,
            config.wethUsdcPoolFee,
            config.wethUsdcTickSpacing,
            config.wethUsdcHooks
        );

        deployed.exitFeeSplitter = new TechExitFeeUsdcSplitter(
            TechExitFeeUsdcSplitter.Addresses({
                owner: deployer,
                tech: address(deployed.tech),
                weth: config.weth,
                usdc: config.usdc,
                vault: address(0),
                poolManager: config.poolManager,
                universalRouter: config.universalRouter,
                permit2: config.permit2,
                ethUsdFeed: config.ethUsdFeed,
                sequencerUptimeFeed: config.sequencerUptimeFeed,
                regentRevenueStaking: config.regentRevenueStaking
            }),
            TechExitFeeUsdcSplitter.Pools({
                techWethPoolKey: techWethPoolKey,
                wethUsdcPoolKey: wethUsdcPoolKey,
                techWethPoolId: PoolId.unwrap(techWethPoolKey.toId()),
                wethUsdcPoolId: PoolId.unwrap(wethUsdcPoolKey.toId()),
                minTechWethLiquidity: config.minTechWethLiquidity,
                minWethUsdcLiquidity: config.minWethUsdcLiquidity
            }),
            TechExitFeeUsdcSplitter.Guards({
                maxEthUsdStalenessSeconds: config.maxEthUsdStalenessSeconds,
                sequencerGracePeriodSeconds: config.sequencerGracePeriodSeconds
            })
        );

        deployed.vault = new TechAgentRewardVault(
            address(deployed.tech),
            config.agentRegistry,
            address(deployed.exitFeeSplitter),
            deployer
        );
        deployed.exitFeeSplitter.setVault(address(deployed.vault));

        deployed.router =
            new TechRewardRouter(address(deployed.tech), address(deployed.vault), deployer);
        deployed.controller = new TechEmissionControllerV2(
            address(deployed.tech),
            address(deployed.vault),
            address(deployed.router),
            config.epochDuration,
            config.maxEpochs,
            config.initialEpochEmission,
            config.maxEmissionSupply,
            config.decayNumerator,
            config.decayDenominator,
            config.owner
        );
        deployed.leaderboardRegistry = new TechLeaderboardRegistry(deployer);
    }

    function _wireRoles(
        DeployedContracts memory deployed,
        DeployConfig memory config,
        address deployer
    ) internal {
        deployed.tech.grantRole(deployed.tech.MINTER_ROLE(), address(deployed.controller));
        deployed.tech.revokeRole(deployed.tech.MINTER_ROLE(), deployer);
        _handoffRole(deployed.tech, deployed.tech.DEFAULT_ADMIN_ROLE(), deployer, config.admin);

        deployed.router
            .grantRole(deployed.router.EMISSION_CONTROLLER_ROLE(), address(deployed.controller));
        deployed.router.grantRole(deployed.router.ROOT_MANAGER_ROLE(), config.rootManager);
        deployed.router.grantRole(deployed.router.PAUSER_ROLE(), config.pauser);
        _revokeIfDifferent(deployed.router, deployed.router.PAUSER_ROLE(), deployer, config.pauser);
        _handoffRole(deployed.router, deployed.router.DEFAULT_ADMIN_ROLE(), deployer, config.admin);

        deployed.vault.grantRole(deployed.vault.REWARD_CREDITOR_ROLE(), address(deployed.router));
        deployed.vault.grantRole(deployed.vault.PAUSER_ROLE(), config.pauser);
        deployed.vault.activateVoting();
        _revokeIfDifferent(deployed.vault, deployed.vault.PAUSER_ROLE(), deployer, config.pauser);
        _handoffRole(deployed.vault, deployed.vault.DEFAULT_ADMIN_ROLE(), deployer, config.admin);

        deployed.leaderboardRegistry
            .grantRole(
                deployed.leaderboardRegistry.LEADERBOARD_MANAGER_ROLE(), config.leaderboardManager
            );
        deployed.leaderboardRegistry
            .grantRole(deployed.leaderboardRegistry.GOVERNANCE_ROLE(), config.owner);
        _revokeIfDifferent(
            deployed.leaderboardRegistry,
            deployed.leaderboardRegistry.LEADERBOARD_MANAGER_ROLE(),
            deployer,
            config.leaderboardManager
        );
        _revokeIfDifferent(
            deployed.leaderboardRegistry,
            deployed.leaderboardRegistry.GOVERNANCE_ROLE(),
            deployer,
            config.owner
        );
        _handoffRole(
            deployed.leaderboardRegistry,
            deployed.leaderboardRegistry.DEFAULT_ADMIN_ROLE(),
            deployer,
            config.admin
        );

        if (config.owner != deployer) {
            deployed.exitFeeSplitter.transferOwnership(config.owner);
        }
    }

    function _deployConfig() internal view returns (DeployConfig memory config) {
        config.admin = _requiredAddress("TECH_ADMIN_ADDRESS");
        config.owner = _requiredAddress("TECH_OWNER_ADDRESS");
        config.rootManager = _requiredAddress("TECH_ROOT_MANAGER_ADDRESS");
        config.leaderboardManager = _requiredAddress("TECH_LEADERBOARD_MANAGER_ADDRESS");
        config.pauser = _requiredAddress("TECH_PAUSER_ADDRESS");
        config.agentRegistry = _requiredAddress("TECH_AGENT_REGISTRY_ADDRESS");
        config.weth = _requiredAddress("TECH_WETH_TOKEN");
        config.usdc = _requiredAddress("TECH_USDC_TOKEN");
        config.regentRevenueStaking = _requiredAddress("TECH_REGENT_REVENUE_STAKING");
        config.poolManager = _requiredAddress("TECH_UNISWAP_V4_POOL_MANAGER");
        config.universalRouter = _requiredAddress("TECH_UNIVERSAL_ROUTER");
        config.permit2 = _requiredAddress("TECH_PERMIT2");
        config.ethUsdFeed = _requiredAddress("TECH_ETH_USD_FEED");
        config.sequencerUptimeFeed = _requiredAddress("TECH_BASE_SEQUENCER_UPTIME_FEED");
        config.maxSupply = vm.envUint("TECH_MAX_SUPPLY");
        config.epochDuration = _envUint64("TECH_EPOCH_DURATION_SECONDS");
        config.maxEpochs = _envUint64("TECH_MAX_EPOCHS");
        config.initialEpochEmission = vm.envUint("TECH_INITIAL_EPOCH_EMISSION");
        config.maxEmissionSupply = vm.envUint("TECH_MAX_EMISSION_SUPPLY");
        config.decayNumerator = vm.envUint("TECH_DECAY_NUMERATOR");
        config.decayDenominator = vm.envUint("TECH_DECAY_DENOMINATOR");
        config.techWethPoolFee = _envUint24("TECH_WETH_POOL_FEE");
        config.techWethTickSpacing = _envInt24("TECH_WETH_POOL_TICK_SPACING");
        config.techWethHooks = vm.envOr("TECH_WETH_POOL_HOOKS", address(0));
        config.wethUsdcPoolFee = _envUint24("WETH_USDC_POOL_FEE");
        config.wethUsdcTickSpacing = _envInt24("WETH_USDC_POOL_TICK_SPACING");
        config.wethUsdcHooks = vm.envOr("WETH_USDC_POOL_HOOKS", address(0));
        config.minTechWethLiquidity = _envUint128("TECH_WETH_MIN_LIQUIDITY");
        config.minWethUsdcLiquidity = _envUint128("WETH_USDC_MIN_LIQUIDITY");
        config.maxEthUsdStalenessSeconds = vm.envUint("TECH_ETH_USD_MAX_STALENESS_SECONDS");
        config.sequencerGracePeriodSeconds = vm.envUint("TECH_SEQUENCER_GRACE_PERIOD_SECONDS");
    }

    function _checkChainId(string memory target) internal view {
        bytes32 targetHash = keccak256(bytes(target));

        if (targetHash == ANVIL_TARGET_HASH) {
            if (block.chainid != ANVIL_CHAIN_ID) {
                revert UnexpectedChainId(ANVIL_CHAIN_ID, block.chainid);
            }
            return;
        }

        if (targetHash == BASE_SEPOLIA_TARGET_HASH) {
            if (block.chainid != BASE_SEPOLIA_CHAIN_ID) {
                revert UnexpectedChainId(BASE_SEPOLIA_CHAIN_ID, block.chainid);
            }
            return;
        }

        if (targetHash == BASE_MAINNET_TARGET_HASH) {
            if (block.chainid != BASE_MAINNET_CHAIN_ID) {
                revert UnexpectedChainId(BASE_MAINNET_CHAIN_ID, block.chainid);
            }
            return;
        }

        revert InvalidDeployTarget(target);
    }

    function _privateKeyForTarget(string memory target) internal view returns (uint256) {
        bytes32 targetHash = keccak256(bytes(target));

        if (targetHash == ANVIL_TARGET_HASH) {
            return vm.envUint("ANVIL_PRIVATE_KEY");
        }

        if (targetHash == BASE_SEPOLIA_TARGET_HASH) {
            return vm.envUint("BASE_SEPOLIA_PRIVATE_KEY");
        }

        if (targetHash == BASE_MAINNET_TARGET_HASH) {
            return vm.envUint("BASE_MAINNET_PRIVATE_KEY");
        }

        revert InvalidDeployTarget(target);
    }

    function _sortedPoolKey(
        address tokenA,
        address tokenB,
        uint24 fee,
        int24 tickSpacing,
        address hooks
    ) internal pure returns (PoolKey memory) {
        (address currency0, address currency1) = uint160(tokenA) < uint160(tokenB)
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        return PoolKey({
            currency0: Currency.wrap(currency0),
            currency1: Currency.wrap(currency1),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hooks)
        });
    }

    function _handoffRole(
        AccessControl target,
        bytes32 role,
        address currentHolder,
        address nextHolder
    ) internal {
        if (nextHolder != currentHolder) {
            target.grantRole(role, nextHolder);
            target.revokeRole(role, currentHolder);
        }
    }

    function _revokeIfDifferent(AccessControl target, bytes32 role, address holder, address keeper)
        internal
    {
        if (holder != keeper && target.hasRole(role, holder)) {
            target.revokeRole(role, holder);
        }
    }

    function _requiredAddress(string memory key) internal view returns (address value) {
        value = vm.envAddress(key);
        if (value == address(0)) revert ZeroAddressConfig(key);
    }

    function _envUint24(string memory key) internal view returns (uint24 value) {
        uint256 raw = vm.envUint(key);
        if (raw > type(uint24).max) revert UintTooLarge(key);
        value = uint24(raw);
    }

    function _envInt24(string memory key) internal view returns (int24 value) {
        int256 raw = vm.envInt(key);
        if (raw > type(int24).max || raw < type(int24).min) revert UintTooLarge(key);
        value = int24(raw);
    }

    function _envUint64(string memory key) internal view returns (uint64 value) {
        uint256 raw = vm.envUint(key);
        if (raw > type(uint64).max) revert UintTooLarge(key);
        value = uint64(raw);
    }

    function _envUint128(string memory key) internal view returns (uint128 value) {
        uint256 raw = vm.envUint(key);
        if (raw > type(uint128).max) revert UintTooLarge(key);
        value = uint128(raw);
    }

    function _resultJson(DeployedContracts memory deployed) internal pure returns (string memory) {
        return string.concat(
            "TECH_STACK_RESULT_JSON:{",
            '"tech":"',
            vm.toString(address(deployed.tech)),
            '","exit_fee_splitter":"',
            vm.toString(address(deployed.exitFeeSplitter)),
            '","agent_reward_vault":"',
            vm.toString(address(deployed.vault)),
            '","reward_router":"',
            vm.toString(address(deployed.router)),
            '","emission_controller":"',
            vm.toString(address(deployed.controller)),
            '","leaderboard_registry":"',
            vm.toString(address(deployed.leaderboardRegistry)),
            '"}'
        );
    }
}
