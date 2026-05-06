// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import { ITechRewardVault } from "./interfaces/ITechRewardVault.sol";

contract TechRewardRouter is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant EMISSION_CONTROLLER_ROLE = keccak256("EMISSION_CONTROLLER_ROLE");
    bytes32 public constant ROOT_MANAGER_ROLE = keccak256("ROOT_MANAGER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    enum RewardLane {
        Science,
        UsdcInput
    }

    struct EpochBudget {
        uint256 totalEmission;
        uint256 scienceBudget;
        uint256 inputBudget;
        uint256 scienceAllocated;
        uint256 inputAllocated;
        bool exists;
    }

    struct AllocationRoot {
        bytes32 merkleRoot;
        uint256 totalAllocated;
        bytes32 manifestHash;
        uint64 challengeEndsAt;
        bool exists;
    }

    IERC20 public immutable TECH;
    ITechRewardVault public immutable vault;
    bool public paused;

    mapping(uint64 => EpochBudget) public epochBudgets;
    mapping(uint64 => mapping(RewardLane => AllocationRoot)) public allocationRoots;
    mapping(bytes32 => bool) public claimed;

    event EpochBudgetRecorded(
        uint64 indexed epoch, uint256 totalEmission, uint256 scienceBudget, uint256 inputBudget
    );
    event AllocationRootPosted(
        uint64 indexed epoch,
        RewardLane indexed lane,
        bytes32 merkleRoot,
        uint256 totalAllocated,
        bytes32 manifestHash,
        uint64 challengeEndsAt
    );
    event RewardClaimed(
        uint64 indexed epoch,
        RewardLane indexed lane,
        uint256 indexed agentId,
        uint256 amount,
        bytes32 allocationRef
    );
    event Paused(address indexed account);
    event Unpaused(address indexed account);

    error ZeroAddress();
    error RootZero();
    error AmountZero();
    error BudgetExists();
    error BudgetMissing();
    error RootExists();
    error RootMissing();
    error ChallengeActive();
    error InvalidProof();
    error AlreadyClaimed();
    error BudgetExceeded();
    error AllowanceLeftOver();
    error PausedState();

    modifier whenNotPaused() {
        if (paused) revert PausedState();
        _;
    }

    constructor(address tech_, address vault_, address admin_) {
        if (tech_ == address(0) || vault_ == address(0) || admin_ == address(0)) {
            revert ZeroAddress();
        }

        TECH = IERC20(tech_);
        vault = ITechRewardVault(vault_);
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(PAUSER_ROLE, admin_);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        paused = false;
        emit Unpaused(msg.sender);
    }

    function recordEpochBudget(
        uint64 epoch,
        uint256 totalEmission,
        uint256 scienceBudget,
        uint256 inputBudget
    ) external onlyRole(EMISSION_CONTROLLER_ROLE) {
        EpochBudget storage budget = epochBudgets[epoch];
        if (budget.exists) revert BudgetExists();
        if (scienceBudget + inputBudget != totalEmission) revert BudgetExceeded();

        epochBudgets[epoch] = EpochBudget({
            totalEmission: totalEmission,
            scienceBudget: scienceBudget,
            inputBudget: inputBudget,
            scienceAllocated: 0,
            inputAllocated: 0,
            exists: true
        });

        emit EpochBudgetRecorded(epoch, totalEmission, scienceBudget, inputBudget);
    }

    function postAllocationRoot(
        uint64 epoch,
        RewardLane lane,
        bytes32 merkleRoot,
        uint256 totalAllocated,
        bytes32 manifestHash,
        uint64 challengeEndsAt
    ) external onlyRole(ROOT_MANAGER_ROLE) whenNotPaused {
        if (merkleRoot == bytes32(0)) revert RootZero();
        if (totalAllocated == 0) revert AmountZero();
        if (allocationRoots[epoch][lane].exists) revert RootExists();

        EpochBudget storage budget = epochBudgets[epoch];
        if (!budget.exists) revert BudgetMissing();

        if (lane == RewardLane.Science) {
            if (budget.scienceAllocated + totalAllocated > budget.scienceBudget) {
                revert BudgetExceeded();
            }
            budget.scienceAllocated += totalAllocated;
        } else {
            if (budget.inputAllocated + totalAllocated > budget.inputBudget) {
                revert BudgetExceeded();
            }
            budget.inputAllocated += totalAllocated;
        }

        allocationRoots[epoch][lane] = AllocationRoot({
            merkleRoot: merkleRoot,
            totalAllocated: totalAllocated,
            manifestHash: manifestHash,
            challengeEndsAt: challengeEndsAt,
            exists: true
        });

        emit AllocationRootPosted(
            epoch, lane, merkleRoot, totalAllocated, manifestHash, challengeEndsAt
        );
    }

    function claim(
        uint64 epoch,
        RewardLane lane,
        uint256 agentId,
        uint256 amount,
        bytes32 allocationRef,
        bytes32[] calldata proof
    ) external nonReentrant whenNotPaused {
        if (amount == 0) revert AmountZero();
        AllocationRoot memory root = allocationRoots[epoch][lane];
        if (!root.exists) revert RootMissing();
        if (root.challengeEndsAt != 0 && block.timestamp < root.challengeEndsAt) {
            revert ChallengeActive();
        }

        bytes32 leaf = allocationLeaf(epoch, lane, agentId, amount, allocationRef);
        if (claimed[leaf]) revert AlreadyClaimed();
        if (!MerkleProof.verifyCalldata(proof, root.merkleRoot, leaf)) revert InvalidProof();

        claimed[leaf] = true;
        uint256 beforeAllowance = TECH.allowance(address(this), address(vault));
        TECH.forceApprove(address(vault), beforeAllowance + amount);
        vault.creditLocked(agentId, amount, allocationRef);
        if (TECH.allowance(address(this), address(vault)) != beforeAllowance) {
            revert AllowanceLeftOver();
        }

        emit RewardClaimed(epoch, lane, agentId, amount, allocationRef);
    }

    function allocationLeaf(
        uint64 epoch,
        RewardLane lane,
        uint256 agentId,
        uint256 amount,
        bytes32 allocationRef
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(epoch, uint8(lane), agentId, amount, allocationRef));
    }
}
