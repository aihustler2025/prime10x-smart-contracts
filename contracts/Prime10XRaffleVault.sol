// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/// @title Prime10X Raffle Reward Vault
/// @author Prime10X Team
/// @notice Trust-minimized vault for distributing TENX rewards to off-chain raffle winners on Base.
/// @dev Each raffle is identified by a unique `raffleId` and verified via Merkle proofs.
///      A global time-lock (TGE + 365 days) can be enforced or disabled by the owner.
contract Prime10XRaffleVault is Ownable2Step, ReentrancyGuard {
    // ------------------------------------------------------------------
    // Types
    // ------------------------------------------------------------------

    /// @notice On-chain configuration for a single raffle.
    /// @param seasonId The season this raffle belongs to.
    /// @param tier Reward tier (0 = Bronze, 1 = Copper, 2 = Silver, 3 = Gold, 4 = Diamond).
    /// @param merkleRoot Merkle root for validating winner claims.
    /// @param totalTenxPool Total TENX allocated to this raffle.
    /// @param totalClaimed Total TENX already claimed from this raffle.
    /// @param active Whether the raffle is currently accepting claims.
    struct Raffle {
        uint256 seasonId;
        uint8 tier;
        bytes32 merkleRoot;
        uint256 totalTenxPool;
        uint256 totalClaimed;
        bool active;
    }

    // ------------------------------------------------------------------
    // State variables
    // ------------------------------------------------------------------

    /// @notice The TENX ERC-20 token distributed by this vault.
    IERC20 public immutable tenxToken;

    /// @dev Mapping of raffleId to its Raffle configuration.
    mapping(uint256 => Raffle) private _raffles;

    /// @dev Tracks whether a user has claimed for a given raffleId.
    mapping(uint256 => mapping(address => bool)) private _hasClaimed;

    /// @dev Total TENX allocated across all raffles.
    uint256 private _totalPoolAllocated;

    /// @dev Total TENX claimed across all raffles.
    uint256 private _totalClaimedOverall;

    /// @dev Timestamp for the Token Generation Event (TGE).
    uint256 private _tgeTimestamp;

    /// @dev Whether the TGE timestamp has been set.
    bool private _tgeSet;

    /// @dev Whether the global lock is enforced. Defaults to true.
    bool private _lockEnforced = true;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------

    /// @notice Emitted when a raffle is created or updated.
    /// @param raffleId The unique identifier of the raffle.
    /// @param seasonId The season this raffle belongs to.
    /// @param tier The reward tier of the raffle.
    /// @param merkleRoot The Merkle root for claim verification.
    /// @param totalTenxPool The total TENX allocated to this raffle.
    /// @param active Whether the raffle is active.
    event RaffleConfigured(
        uint256 indexed raffleId,
        uint256 seasonId,
        uint8 tier,
        bytes32 merkleRoot,
        uint256 totalTenxPool,
        bool active
    );

    /// @notice Emitted when a user successfully claims raffle rewards.
    /// @param user The address that claimed.
    /// @param raffleId The raffle that was claimed from.
    /// @param amount The amount of TENX claimed.
    event RaffleClaimed(address indexed user, uint256 indexed raffleId, uint256 amount);

    /// @notice Emitted when the TGE timestamp is set.
    /// @param tgeTimestamp The configured TGE timestamp.
    event TGETimestampSet(uint256 tgeTimestamp);

    /// @notice Emitted when lock enforcement is toggled.
    /// @param enforced Whether the lock is now enforced.
    event LockEnforcedUpdated(bool enforced);

    /// @notice Emitted when tokens are rescued from the vault.
    /// @param token The token address that was rescued.
    /// @param to The recipient of the rescued tokens.
    /// @param amount The amount of tokens rescued.
    event TokensRescued(address indexed token, address indexed to, uint256 amount);

    // ------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------

    /// @notice Deploys the raffle vault bound to the given TENX token and initial owner.
    /// @param tenxToken_ TENX ERC-20 token address.
    /// @param owner_ Initial owner address.
    constructor(address tenxToken_, address owner_) Ownable(owner_) {
        require(tenxToken_ != address(0), "RaffleVault: zero token");
        tenxToken = IERC20(tenxToken_);
    }

    // =============================================================
    // Raffle Management
    // =============================================================

    /// @notice Create a new raffle or update an existing one.
    /// @dev When updating, `totalTenxPool` must be >= the raffle's `totalClaimed`.
    /// @param raffleId Unique identifier for the raffle.
    /// @param seasonId Season identifier (must be > 0).
    /// @param tier Reward tier (0-4).
    /// @param merkleRoot Merkle root for winner verification.
    /// @param totalTenxPool Total TENX allocated to this raffle.
    /// @param active Whether the raffle should be active.
    function createOrUpdateRaffle(
        uint256 raffleId,
        uint256 seasonId,
        uint8 tier,
        bytes32 merkleRoot,
        uint256 totalTenxPool,
        bool active
    ) external onlyOwner {
        require(seasonId > 0, "RaffleVault: invalid raffle");
        require(tier <= 4, "RaffleVault: invalid raffle");
        require(merkleRoot != bytes32(0), "RaffleVault: invalid raffle");
        require(totalTenxPool > 0, "RaffleVault: invalid raffle");

        Raffle storage raffle = _raffles[raffleId];
        bool existed = raffle.totalTenxPool > 0;

        if (existed) {
            require(totalTenxPool >= raffle.totalClaimed, "RaffleVault: insufficient pool");
            _totalPoolAllocated = _totalPoolAllocated - raffle.totalTenxPool + totalTenxPool;
        } else {
            _totalPoolAllocated += totalTenxPool;
        }

        raffle.seasonId = seasonId;
        raffle.tier = tier;
        raffle.merkleRoot = merkleRoot;
        raffle.totalTenxPool = totalTenxPool;
        raffle.active = active;

        emit RaffleConfigured(raffleId, seasonId, tier, merkleRoot, totalTenxPool, active);
    }

    /// @notice Activate or deactivate an existing raffle.
    /// @param raffleId The raffle to update.
    /// @param active Whether the raffle should be active.
    function setRaffleActive(uint256 raffleId, bool active) external onlyOwner {
        Raffle storage raffle = _raffles[raffleId];
        require(raffle.totalTenxPool > 0, "RaffleVault: invalid raffle");
        raffle.active = active;
        emit RaffleConfigured(raffleId, raffle.seasonId, raffle.tier, raffle.merkleRoot, raffle.totalTenxPool, active);
    }

    /// @notice Get details of a raffle.
    /// @param raffleId The raffle to query.
    /// @return seasonId The season identifier.
    /// @return tier The reward tier.
    /// @return merkleRoot The Merkle root.
    /// @return totalTenxPool The total TENX pool size.
    /// @return totalClaimed The total TENX already claimed.
    /// @return active Whether the raffle is active.
    function getRaffle(uint256 raffleId)
        external
        view
        returns (uint256 seasonId, uint8 tier, bytes32 merkleRoot, uint256 totalTenxPool, uint256 totalClaimed, bool active)
    {
        Raffle storage raffle = _raffles[raffleId];
        return (raffle.seasonId, raffle.tier, raffle.merkleRoot, raffle.totalTenxPool, raffle.totalClaimed, raffle.active);
    }

    // =============================================================
    // Claiming
    // =============================================================

    /// @notice Claim TENX rewards for a raffle using a Merkle proof.
    /// @dev The leaf is computed as `keccak256(abi.encodePacked(msg.sender, raffleId, tenxAmount))`.
    /// @param raffleId The raffle to claim from.
    /// @param tenxAmount The amount of TENX to claim (must match the Merkle leaf).
    /// @param merkleProof The Merkle proof validating the claim.
    /// @custom:security Protected by ReentrancyGuard. Each address can only claim once per raffle.
    function claim(uint256 raffleId, uint256 tenxAmount, bytes32[] calldata merkleProof) external nonReentrant {
        Raffle storage raffle = _raffles[raffleId];
        require(raffle.totalTenxPool > 0, "RaffleVault: invalid raffle");
        require(raffle.active, "RaffleVault: raffle inactive");
        require(tenxAmount > 0, "RaffleVault: invalid amount");

        if (_lockEnforced) {
            require(_tgeSet, "RaffleVault: TGE not set");
            require(block.timestamp >= _tgeTimestamp + 365 days, "RaffleVault: not unlocked yet");
        }

        require(!_hasClaimed[raffleId][msg.sender], "RaffleVault: already claimed");

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(msg.sender, raffleId, tenxAmount))));
        bool validProof = MerkleProof.verify(merkleProof, raffle.merkleRoot, leaf);
        require(validProof, "RaffleVault: invalid proof");

        require(raffle.totalClaimed + tenxAmount <= raffle.totalTenxPool, "RaffleVault: insufficient pool");

        _hasClaimed[raffleId][msg.sender] = true;
        raffle.totalClaimed += tenxAmount;
        _totalClaimedOverall += tenxAmount;

        emit RaffleClaimed(msg.sender, raffleId, tenxAmount);

        require(tenxToken.transfer(msg.sender, tenxAmount), "RaffleVault: transfer failed");
    }

    /// @notice Check whether a user has claimed a specific raffle.
    /// @param raffleId The raffle to check.
    /// @param user The address to check.
    /// @return Whether the user has already claimed this raffle.
    function hasClaimed(uint256 raffleId, address user) external view returns (bool) {
        return _hasClaimed[raffleId][user];
    }

    /// @notice Returns whether a claim would be valid and whether it was already claimed.
    /// @param raffleId The raffle to check.
    /// @param user The address to check.
    /// @param tenxAmount The amount to verify.
    /// @param merkleProof The Merkle proof to verify.
    /// @return valid Whether the claim would succeed.
    /// @return alreadyClaimed Whether the user has already claimed.
    function claimableFor(uint256 raffleId, address user, uint256 tenxAmount, bytes32[] calldata merkleProof)
        external
        view
        returns (bool valid, bool alreadyClaimed)
    {
        Raffle storage raffle = _raffles[raffleId];
        if (raffle.totalTenxPool == 0 || !raffle.active || tenxAmount == 0) {
            return (false, _hasClaimed[raffleId][user]);
        }

        if (_lockEnforced) {
            if (!_tgeSet || block.timestamp < _tgeTimestamp + 365 days) {
                return (false, _hasClaimed[raffleId][user]);
            }
        }

        if (raffle.totalClaimed + tenxAmount > raffle.totalTenxPool) {
            return (false, _hasClaimed[raffleId][user]);
        }

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(user, raffleId, tenxAmount))));
        bool validProof = MerkleProof.verify(merkleProof, raffle.merkleRoot, leaf);
        return (validProof, _hasClaimed[raffleId][user]);
    }

    // =============================================================
    // Locking / TGE
    // =============================================================

    /// @notice Set the TGE timestamp. Can only be set once.
    /// @param tgeTimestamp The TGE timestamp (must be in the future).
    /// @custom:security One-shot function — cannot be called again once set.
    function setTGETimestamp(uint256 tgeTimestamp) external onlyOwner {
        require(!_tgeSet, "RaffleVault: TGE already set");
        require(tgeTimestamp > block.timestamp, "RaffleVault: TGE must be in future");
        _tgeTimestamp = tgeTimestamp;
        _tgeSet = true;
        emit TGETimestampSet(tgeTimestamp);
    }

    /// @notice Enable or disable lock enforcement.
    /// @dev When disabled, claims are allowed regardless of TGE status.
    /// @param enforced Whether to enforce the time lock.
    function setLockEnforced(bool enforced) external onlyOwner {
        _lockEnforced = enforced;
        emit LockEnforcedUpdated(enforced);
    }

    /// @notice Returns whether claims are currently unlocked.
    /// @return True if lock is disabled or if TGE is set and lock period has elapsed.
    function isUnlocked() public view returns (bool) {
        if (!_lockEnforced) {
            return true;
        }
        if (!_tgeSet) {
            return false;
        }
        return block.timestamp >= _tgeTimestamp + 365 days;
    }

    /// @notice Returns the unlock timestamp if TGE is set, otherwise 0.
    /// @return The timestamp after which claims are allowed (when lock is enforced).
    function getUnlockTime() external view returns (uint256) {
        if (!_tgeSet) {
            return 0;
        }
        return _tgeTimestamp + 365 days;
    }

    /// @notice Returns the configured TGE timestamp and whether it has been set.
    /// @return tgeTimestamp The TGE timestamp.
    /// @return tgeSet Whether the TGE has been configured.
    function getTGETimestamp() external view returns (uint256 tgeTimestamp, bool tgeSet) {
        return (_tgeTimestamp, _tgeSet);
    }

    // =============================================================
    // Funding & Rescue
    // =============================================================

    /// @notice Current TENX balance held by the vault.
    /// @return The TENX balance of this contract.
    function vaultBalance() public view returns (uint256) {
        return tenxToken.balanceOf(address(this));
    }

    /// @notice Returns total TENX allocated across all raffles.
    /// @return The cumulative pool allocation.
    function totalPoolAllocated() external view returns (uint256) {
        return _totalPoolAllocated;
    }

    /// @notice Returns total TENX claimed across all raffles.
    /// @return The cumulative amount claimed.
    function totalClaimedOverall() external view returns (uint256) {
        return _totalClaimedOverall;
    }

    /// @notice Rescue tokens mistakenly sent to the vault.
    /// @dev TENX withdrawals are limited to preserve unclaimed allocations.
    /// @param token Address of the ERC-20 token to rescue.
    /// @param to Recipient of the rescued tokens.
    /// @param amount Amount of tokens to rescue.
    /// @custom:security TENX rescue requires vault balance to remain >= total unclaimed pool.
    function rescueTokens(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0), "RaffleVault: invalid recipient");
        require(amount > 0, "RaffleVault: invalid amount");

        if (token == address(tenxToken)) {
            uint256 totalUnclaimedPool = _totalPoolAllocated - _totalClaimedOverall;
            uint256 balance = tenxToken.balanceOf(address(this));
            require(balance >= totalUnclaimedPool + amount, "RaffleVault: insufficient pool");
            require(tenxToken.transfer(to, amount), "RaffleVault: transfer failed");
        } else {
            require(IERC20(token).transfer(to, amount), "RaffleVault: transfer failed");
        }

        emit TokensRescued(token, to, amount);
    }
}
