// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { TechEpochMath } from "./libraries/TechEpochMath.sol";
import { ITechRewardRouter } from "./interfaces/ITechRewardRouter.sol";
import { ITechRewardVault } from "./interfaces/ITechRewardVault.sol";

interface ITechMintableV2 {
    function mint(address to, uint256 amount) external;
}

contract TechEmissionControllerV2 is Ownable, ReentrancyGuard {
    uint256 public constant WAD = 1e18;

    ITechMintableV2 public immutable TECH;
    ITechRewardVault public immutable scienceShareSource;
    ITechRewardRouter public immutable rewardRouter;

    uint64 public immutable epochDuration;
    uint64 public immutable maxEpochs;
    uint256 public immutable maxEmissionSupply;
    uint256 public immutable decayNumerator;
    uint256 public immutable decayDenominator;

    uint64 public currentEpoch;
    uint64 public currentEpochStart;
    uint256 public currentScienceShareWad;
    uint256 public currentEpochEmission;
    uint256 public totalEmitted;

    event EpochSettled(
        uint64 indexed epoch,
        uint256 epochEmission,
        uint256 scienceShareWad,
        uint256 scienceAmount,
        uint256 inputAmount
    );
    event NextEpochConfigured(
        uint64 indexed nextEpoch,
        uint256 scienceShareWad,
        uint256 inputShareWad,
        uint256 nextEpochEmission
    );

    error ZeroAddress();
    error ZeroValue();
    error InvalidDecayRatio();
    error EpochActive();
    error InvalidScienceShare();

    constructor(
        address tech_,
        address scienceShareSource_,
        address rewardRouter_,
        uint64 epochDuration_,
        uint64 maxEpochs_,
        uint256 initialEpochEmission_,
        uint256 maxEmissionSupply_,
        uint256 decayNumerator_,
        uint256 decayDenominator_,
        address owner_
    ) Ownable(owner_) {
        if (
            tech_ == address(0) || scienceShareSource_ == address(0) || rewardRouter_ == address(0)
                || owner_ == address(0)
        ) {
            revert ZeroAddress();
        }
        if (
            epochDuration_ == 0 || maxEpochs_ == 0 || initialEpochEmission_ == 0
                || maxEmissionSupply_ == 0 || decayNumerator_ == 0 || decayDenominator_ == 0
        ) {
            revert ZeroValue();
        }
        if (decayNumerator_ >= decayDenominator_) revert InvalidDecayRatio();

        TECH = ITechMintableV2(tech_);
        scienceShareSource = ITechRewardVault(scienceShareSource_);
        rewardRouter = ITechRewardRouter(rewardRouter_);
        epochDuration = epochDuration_;
        maxEpochs = maxEpochs_;
        currentEpochEmission = initialEpochEmission_;
        maxEmissionSupply = maxEmissionSupply_;
        decayNumerator = decayNumerator_;
        decayDenominator = decayDenominator_;
        currentEpochStart = uint64(block.timestamp);
        currentScienceShareWad = WAD;
    }

    function rollEpoch() external nonReentrant {
        if (block.timestamp < uint256(currentEpochStart) + uint256(epochDuration)) {
            revert EpochActive();
        }

        uint64 settledEpoch = currentEpoch;
        uint256 settledScienceShare = currentScienceShareWad;
        uint256 emission = _emissionForCurrentEpoch();
        uint256 scienceAmount = Math.mulDiv(emission, settledScienceShare, WAD);
        uint256 inputAmount = emission - scienceAmount;

        if (emission != 0) {
            totalEmitted += emission;
            TECH.mint(address(rewardRouter), emission);
        }

        rewardRouter.recordEpochBudget(settledEpoch, emission, scienceAmount, inputAmount);

        uint256 nextScienceShare = scienceShareSource.scienceShareWad();
        if (nextScienceShare > WAD) revert InvalidScienceShare();

        uint256 nextEmission =
            TechEpochMath.nextEmission(currentEpochEmission, decayNumerator, decayDenominator);

        currentEpoch = settledEpoch + 1;
        currentEpochStart = uint64(block.timestamp);
        currentScienceShareWad = nextScienceShare;
        currentEpochEmission = nextEmission;

        emit EpochSettled(settledEpoch, emission, settledScienceShare, scienceAmount, inputAmount);
        emit NextEpochConfigured(
            currentEpoch, nextScienceShare, WAD - nextScienceShare, nextEmission
        );
    }

    function epochEndsAt() external view returns (uint256) {
        return uint256(currentEpochStart) + uint256(epochDuration);
    }

    function currentInputShareWad() external view returns (uint256) {
        return WAD - currentScienceShareWad;
    }

    function previewNextScienceShareWad() external view returns (uint256) {
        return scienceShareSource.scienceShareWad();
    }

    function previewNextEpochEmission() external view returns (uint256) {
        return TechEpochMath.nextEmission(currentEpochEmission, decayNumerator, decayDenominator);
    }

    function remainingEmissionBudget() public view returns (uint256) {
        return maxEmissionSupply - totalEmitted;
    }

    function _emissionForCurrentEpoch() internal view returns (uint256) {
        if (currentEpoch >= maxEpochs || totalEmitted >= maxEmissionSupply) {
            return 0;
        }

        uint256 remaining = remainingEmissionBudget();
        return currentEpochEmission > remaining ? remaining : currentEpochEmission;
    }
}
