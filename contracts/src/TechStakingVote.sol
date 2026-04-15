// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/// @notice Single-pool TECH staking with one liquid receipt token (stTECH)
/// and one per-holder science-wall preference p in [0, 1e18].
///
/// science share for emissions = totalScienceWeighted / totalStaked
/// where totalScienceWeighted = sum_i floor(balance_i * preference_i / 1e18)
contract TechStakingVote is ERC20, ERC20Permit, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant WAD = 1e18;

    IERC20 public immutable TECH;

    /// @dev One-time activation switch. Before activation, the emission split
    /// should be treated as 100% science-wall by the emission controller.
    bool public votingActivated;

    /// @dev Exact aggregate science-weighted stake in underlying TECH units.
    uint256 public totalScienceWeighted;

    mapping(address => uint256) private _sciencePreferenceWad;
    mapping(address => bool) private _hasExplicitPreference;

    event Deposited(address indexed caller, address indexed receiver, uint256 amount);
    event Withdrawn(address indexed caller, address indexed receiver, uint256 amount);
    event PreferenceSet(
        address indexed account, uint256 oldPreferenceWad, uint256 newPreferenceWad
    );
    event VotingActivated();

    constructor(address tech_, address owner_)
        ERC20("Staked Tech", "stTECH")
        ERC20Permit("Staked Tech")
        Ownable(owner_)
    {
        require(tech_ != address(0), "TECH=0");
        TECH = IERC20(tech_);
    }

    function activateVoting() external onlyOwner {
        require(!votingActivated, "already activated");
        votingActivated = true;
        emit VotingActivated();
    }

    /// @notice Returns the holder's science-wall preference in WAD.
    /// Unset holders default to 100% science-wall.
    function sciencePreferenceWad(address account) public view returns (uint256) {
        if (_hasExplicitPreference[account]) {
            return _sciencePreferenceWad[account];
        }
        return WAD;
    }

    function deposit(uint256 amount) external nonReentrant {
        _deposit(msg.sender, msg.sender, amount);
    }

    function depositFor(address receiver, uint256 amount) external nonReentrant {
        _deposit(msg.sender, receiver, amount);
    }

    function depositAndSetPreference(uint256 amount, uint256 newPreferenceWad)
        external
        nonReentrant
    {
        _setPreference(msg.sender, newPreferenceWad);
        _deposit(msg.sender, msg.sender, amount);
    }

    function withdraw(uint256 amount, address receiver) external nonReentrant {
        require(receiver != address(0), "receiver=0");
        _burn(msg.sender, amount);
        TECH.safeTransfer(receiver, amount);
        emit Withdrawn(msg.sender, receiver, amount);
    }

    function setPreference(uint256 newPreferenceWad) external {
        _setPreference(msg.sender, newPreferenceWad);
    }

    /// @notice Science-wall share in WAD for the next epoch boundary snapshot.
    /// Before activation, this returns 100% science-wall.
    function scienceShareWad() external view returns (uint256) {
        return currentScienceShareWad();
    }

    function currentScienceShareWad() public view returns (uint256) {
        uint256 supply = totalSupply();
        if (!votingActivated || supply == 0) {
            return WAD;
        }
        return Math.mulDiv(totalScienceWeighted, WAD, supply);
    }

    function currentResearchRevenueShareWad() external view returns (uint256) {
        return WAD - currentScienceShareWad();
    }

    function _deposit(address from, address receiver, uint256 amount) internal {
        require(receiver != address(0), "receiver=0");
        require(amount > 0, "amount=0");
        TECH.safeTransferFrom(from, address(this), amount);
        _mint(receiver, amount);
        emit Deposited(from, receiver, amount);
    }

    function _setPreference(address account, uint256 newPreferenceWad) internal {
        require(newPreferenceWad <= WAD, "pref>1");

        uint256 oldPreferenceWad = sciencePreferenceWad(account);
        if (_hasExplicitPreference[account] && oldPreferenceWad == newPreferenceWad) {
            return;
        }

        uint256 bal = balanceOf(account);
        if (bal > 0) {
            _applyContributionChange(
                _weightedStake(bal, oldPreferenceWad), _weightedStake(bal, newPreferenceWad)
            );
        }

        _sciencePreferenceWad[account] = newPreferenceWad;
        _hasExplicitPreference[account] = true;

        emit PreferenceSet(account, oldPreferenceWad, newPreferenceWad);
    }

    function _weightedStake(uint256 amount, uint256 preferenceWad) internal pure returns (uint256) {
        return Math.mulDiv(amount, preferenceWad, WAD);
    }

    function _applyContributionChange(uint256 oldContribution, uint256 newContribution) internal {
        if (newContribution > oldContribution) {
            totalScienceWeighted += (newContribution - oldContribution);
        } else if (oldContribution > newContribution) {
            totalScienceWeighted -= (oldContribution - newContribution);
        }
    }

    function _adjustWeightedStakeForBalanceChange(
        address account,
        uint256 oldBalance,
        uint256 newBalance
    ) internal {
        uint256 preferenceWad = sciencePreferenceWad(account);
        _applyContributionChange(
            _weightedStake(oldBalance, preferenceWad), _weightedStake(newBalance, preferenceWad)
        );
    }

    /// @dev Keep totalScienceWeighted exact by recomputing per-holder contribution
    /// before and after every mint / burn / transfer.
    function _update(address from, address to, uint256 value) internal override {
        if (value == 0 || from == to) {
            super._update(from, to, value);
            return;
        }

        if (from != address(0)) {
            uint256 fromOldBalance = balanceOf(from);
            _adjustWeightedStakeForBalanceChange(from, fromOldBalance, fromOldBalance - value);
        }

        if (to != address(0)) {
            uint256 toOldBalance = balanceOf(to);
            _adjustWeightedStakeForBalanceChange(to, toOldBalance, toOldBalance + value);
        }

        super._update(from, to, value);
    }
}
