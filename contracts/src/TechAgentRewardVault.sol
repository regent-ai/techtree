// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IAgentRegistryLike } from "./interfaces/IAgentRegistryLike.sol";
import { ITechExitSwap } from "./interfaces/ITechExitSwap.sol";

contract TechAgentRewardVault is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant REWARD_CREDITOR_ROLE = keccak256("REWARD_CREDITOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    uint256 public constant WAD = 1e18;
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant EXIT_SALE_BPS = 1_000;

    IERC20 public immutable TECH;
    IAgentRegistryLike public immutable agentRegistry;
    ITechExitSwap public exitSwap;

    bool public paused;
    bool public votingActivated;
    uint256 public totalLockedTech;
    uint256 public totalScienceWeighted;

    mapping(uint256 => uint256) public lockedBalance;
    mapping(uint256 => uint256) private _sciencePreferenceWad;
    mapping(uint256 => bool) private _hasExplicitPreference;

    event LockedTechCredited(uint256 indexed agentId, uint256 amount, bytes32 indexed sourceRef);
    event LockedTechWithdrawn(
        uint256 indexed agentId,
        address indexed owner,
        address indexed techRecipient,
        address regentRecipient,
        uint256 amount,
        uint256 liquidTechAmount,
        uint256 soldTechAmount,
        uint256 techToWethOut,
        uint256 regentOut
    );
    event SciencePreferenceSet(
        uint256 indexed agentId, uint256 oldPreferenceWad, uint256 newPreferenceWad
    );
    event VotingActivated();
    event ExitSwapSet(address indexed previousExitSwap, address indexed newExitSwap);
    event Paused(address indexed account);
    event Unpaused(address indexed account);

    error ZeroAddress();
    error ZeroAmount();
    error SourceRefZero();
    error PreferenceTooHigh();
    error OnlyAgentOwner();
    error InsufficientLockedBalance();
    error SaleAmountZero();
    error PausedState();

    modifier whenNotPaused() {
        if (paused) revert PausedState();
        _;
    }

    constructor(address tech_, address agentRegistry_, address exitSwap_, address admin_) {
        if (
            tech_ == address(0) || agentRegistry_ == address(0) || exitSwap_ == address(0)
                || admin_ == address(0)
        ) {
            revert ZeroAddress();
        }

        TECH = IERC20(tech_);
        agentRegistry = IAgentRegistryLike(agentRegistry_);
        exitSwap = ITechExitSwap(exitSwap_);
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(PAUSER_ROLE, admin_);
    }

    function setExitSwap(address exitSwap_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (exitSwap_ == address(0)) revert ZeroAddress();
        address previous = address(exitSwap);
        exitSwap = ITechExitSwap(exitSwap_);
        emit ExitSwapSet(previous, exitSwap_);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        paused = false;
        emit Unpaused(msg.sender);
    }

    function activateVoting() external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!votingActivated, "ALREADY_ACTIVE");
        votingActivated = true;
        emit VotingActivated();
    }

    function creditLocked(uint256 agentId, uint256 amount, bytes32 sourceRef)
        external
        onlyRole(REWARD_CREDITOR_ROLE)
        nonReentrant
        whenNotPaused
    {
        if (amount == 0) revert ZeroAmount();
        if (sourceRef == bytes32(0)) revert SourceRefZero();

        _setLockedBalance(agentId, lockedBalance[agentId] + amount);
        totalLockedTech += amount;

        TECH.safeTransferFrom(msg.sender, address(this), amount);

        emit LockedTechCredited(agentId, amount, sourceRef);
    }

    function withdraw(
        uint256 agentId,
        uint256 amount,
        address techRecipient,
        address regentRecipient,
        uint256 minRegentOut,
        uint256 deadline
    ) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        if (techRecipient == address(0) || regentRecipient == address(0)) revert ZeroAddress();
        if (agentRegistry.ownerOf(agentId) != msg.sender) revert OnlyAgentOwner();

        uint256 currentLocked = lockedBalance[agentId];
        if (currentLocked < amount) revert InsufficientLockedBalance();

        uint256 saleAmount = Math.mulDiv(amount, EXIT_SALE_BPS, BPS_DENOMINATOR);
        if (saleAmount == 0) revert SaleAmountZero();
        uint256 liquidAmount = amount - saleAmount;

        _setLockedBalance(agentId, currentLocked - amount);
        totalLockedTech -= amount;

        TECH.safeTransfer(address(exitSwap), saleAmount);
        (uint256 techToWethOut, uint256 regentOut) =
            exitSwap.sellTechForRegent(saleAmount, minRegentOut, deadline, regentRecipient);
        TECH.safeTransfer(techRecipient, liquidAmount);

        emit LockedTechWithdrawn(
            agentId,
            msg.sender,
            techRecipient,
            regentRecipient,
            amount,
            liquidAmount,
            saleAmount,
            techToWethOut,
            regentOut
        );
    }

    function setSciencePreference(uint256 agentId, uint256 preferenceWad) external {
        if (preferenceWad > WAD) revert PreferenceTooHigh();
        if (agentRegistry.ownerOf(agentId) != msg.sender) revert OnlyAgentOwner();

        uint256 oldPreference = sciencePreferenceWad(agentId);
        if (_hasExplicitPreference[agentId] && oldPreference == preferenceWad) {
            return;
        }

        uint256 balance = lockedBalance[agentId];
        if (balance != 0) {
            _applyContributionChange(
                _weightedStake(balance, oldPreference), _weightedStake(balance, preferenceWad)
            );
        }

        _sciencePreferenceWad[agentId] = preferenceWad;
        _hasExplicitPreference[agentId] = true;

        emit SciencePreferenceSet(agentId, oldPreference, preferenceWad);
    }

    function sciencePreferenceWad(uint256 agentId) public view returns (uint256) {
        if (_hasExplicitPreference[agentId]) {
            return _sciencePreferenceWad[agentId];
        }

        return WAD;
    }

    function scienceShareWad() external view returns (uint256) {
        return currentScienceShareWad();
    }

    function currentScienceShareWad() public view returns (uint256) {
        if (!votingActivated || totalLockedTech == 0) {
            return WAD;
        }

        return Math.mulDiv(totalScienceWeighted, WAD, totalLockedTech);
    }

    function _setLockedBalance(uint256 agentId, uint256 newBalance) internal {
        uint256 oldBalance = lockedBalance[agentId];
        if (oldBalance == newBalance) return;

        _applyContributionChange(
            _weightedStake(oldBalance, sciencePreferenceWad(agentId)),
            _weightedStake(newBalance, sciencePreferenceWad(agentId))
        );
        lockedBalance[agentId] = newBalance;
    }

    function _weightedStake(uint256 amount, uint256 preferenceWad) internal pure returns (uint256) {
        return Math.mulDiv(amount, preferenceWad, WAD);
    }

    function _applyContributionChange(uint256 oldContribution, uint256 newContribution) internal {
        if (newContribution > oldContribution) {
            totalScienceWeighted += newContribution - oldContribution;
        } else if (oldContribution > newContribution) {
            totalScienceWeighted -= oldContribution - newContribution;
        }
    }
}
