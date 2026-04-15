// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

interface ITechMintable {
    function mint(address to, uint256 amount) external;
}

interface ITechStakingVote {
    function scienceShareWad() external view returns (uint256);
}

/// @notice Settles one epoch at a time.
///
/// The split for the *current* epoch is stored in currentScienceShareWad.
/// Each epoch must last at least epochDuration, but the epoch only advances when
/// rollEpoch() is called. The live staking split observed during that roll
/// becomes the locked split for the next epoch.
contract TechEmissionController is Ownable {
    uint256 public constant WAD = 1e18;

    ITechMintable public immutable TECH;
    ITechStakingVote public immutable STAKING;

    address public scienceWallDistributor;
    address public researchRevenueDistributor;

    uint64 public immutable epochDuration;
    uint64 public immutable halvingIntervalEpochs;
    uint256 public immutable initialEpochEmission;

    uint64 public currentEpoch;
    uint64 public currentEpochStart;
    uint256 public currentScienceShareWad;

    event EpochSettled(
        uint64 indexed epoch,
        uint256 epochEmission,
        uint256 scienceShareWad,
        uint256 scienceAmount,
        uint256 researchRevenueAmount
    );
    event NextEpochConfigured(
        uint64 indexed nextEpoch, uint256 scienceShareWad, uint256 researchRevenueShareWad
    );
    event DistributorsUpdated(
        address indexed scienceWallDistributor, address indexed researchRevenueDistributor
    );

    constructor(
        address tech_,
        address staking_,
        address scienceWallDistributor_,
        address researchRevenueDistributor_,
        uint64 epochDuration_,
        uint64 halvingIntervalEpochs_,
        uint256 initialEpochEmission_,
        address owner_
    ) Ownable(owner_) {
        require(tech_ != address(0), "TECH=0");
        require(staking_ != address(0), "STAKING=0");
        require(scienceWallDistributor_ != address(0), "scienceDist=0");
        require(researchRevenueDistributor_ != address(0), "rrDist=0");
        require(epochDuration_ > 0, "epoch=0");
        require(halvingIntervalEpochs_ > 0, "halving=0");

        TECH = ITechMintable(tech_);
        STAKING = ITechStakingVote(staking_);
        scienceWallDistributor = scienceWallDistributor_;
        researchRevenueDistributor = researchRevenueDistributor_;
        epochDuration = epochDuration_;
        halvingIntervalEpochs = halvingIntervalEpochs_;
        initialEpochEmission = initialEpochEmission_;

        currentEpoch = 0;
        currentEpochStart = uint64(block.timestamp);
        currentScienceShareWad = WAD; // bootstrap epoch starts 100% science-wall
    }

    function setDistributors(address scienceWallDistributor_, address researchRevenueDistributor_)
        external
        onlyOwner
    {
        require(scienceWallDistributor_ != address(0), "scienceDist=0");
        require(researchRevenueDistributor_ != address(0), "rrDist=0");
        scienceWallDistributor = scienceWallDistributor_;
        researchRevenueDistributor = researchRevenueDistributor_;
        emit DistributorsUpdated(scienceWallDistributor_, researchRevenueDistributor_);
    }

    function epochEndsAt() external view returns (uint256) {
        return uint256(currentEpochStart) + uint256(epochDuration);
    }

    function currentResearchRevenueShareWad() external view returns (uint256) {
        return WAD - currentScienceShareWad;
    }

    function previewNextScienceShareWad() external view returns (uint256) {
        return STAKING.scienceShareWad();
    }

    function emissionForEpoch(uint256 epoch) public view returns (uint256) {
        uint256 halvings = epoch / uint256(halvingIntervalEpochs);
        if (halvings >= 256) return 0;
        return initialEpochEmission >> halvings;
    }

    /// @notice Settles the just-finished epoch and configures the next one.
    function rollEpoch() external {
        require(
            block.timestamp >= uint256(currentEpochStart) + uint256(epochDuration), "epoch active"
        );

        uint256 emission = emissionForEpoch(currentEpoch);
        uint256 scienceAmount = Math.mulDiv(emission, currentScienceShareWad, WAD);
        uint256 researchRevenueAmount = emission - scienceAmount;

        if (scienceAmount > 0) {
            TECH.mint(scienceWallDistributor, scienceAmount);
        }
        if (researchRevenueAmount > 0) {
            TECH.mint(researchRevenueDistributor, researchRevenueAmount);
        }

        emit EpochSettled(
            currentEpoch, emission, currentScienceShareWad, scienceAmount, researchRevenueAmount
        );

        uint64 nextEpoch = currentEpoch + 1;
        uint256 nextScienceShareWad = STAKING.scienceShareWad();

        currentEpoch = nextEpoch;
        currentEpochStart = uint64(block.timestamp);
        currentScienceShareWad = nextScienceShareWad;

        emit NextEpochConfigured(nextEpoch, nextScienceShareWad, WAD - nextScienceShareWad);
    }
}
