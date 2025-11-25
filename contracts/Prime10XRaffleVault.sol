// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/// @title Prime10X Raffle Reward Vault
/// @notice Trust-minimized vault for distributing TENX rewards to off-chain raffle winners on Base.
contract Prime10XRaffleVault is Ownable, ReentrancyGuard {
    /// @notice Raffle details stored on-chain.
    struct Raffle {
        uint256 seasonId;
        uint8 tier; // 0=Bronze,1=Copper,2=Silver,3=Gold,4=Diamond
        bytes32 merkleRoot;
        uint256 totalTenxPool;
        uint256 totalClaimed;
        bool active;
    }

    /// @notice TENX token distributed by the vault.
    IERC20 public immutable tenxToken;

    /// @notice Mapping of raffleId to raffle configuration.
    mapping(uint256 => Raffle) private _raffles;

    /// @notice Tracks whether a user has claimed for a given raffleId.
    mapping(uint256 => mapping(address => bool)) private _hasClaimed;

    /// @notice Total TENX allocated across all raffles.
    uint256 private _totalPoolAllocated;

    /// @notice Total TENX claimed across all raffles.
    uint256 private _totalClaimedOverall;

    /// @notice Timestamp for the Token Generation Event (TGE).
    uint256 private _tgeTimestamp;

    /// @notice Whether the TGE timestamp has been set.
    bool private _tgeSet;

    /// @notice Whether the global lock is enforced. Defaults to true.
    bool private _lockEnforced = true;

    /// @notice Emitted when a raffle is created or updated.
    event RaffleConfigured(
        uint256 indexed raffleId,
        uint256 seasonId,
        uint8 tier,
        bytes32 merkleRoot,
        uint256 totalTenxPool,
        bool active
    );

    /// @notice Emitted when a user successfully claims raffle rewards.
    event RaffleClaimed(address indexed user, uint256 indexed raffleId, uint256 amount);

    /// @notice Emitted when the TGE timestamp is set.
    event TGETimestampSet(uint256 tgeTimestamp);

    /// @notice Emitted when lock enforcement is toggled.
    event LockEnforcedUpdated(bool enforced);

    /// @notice Emitted when tokens are rescued from the vault.
    event TokensRescued(address indexed token, address indexed to, uint256 amount);

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
    /// @dev totalTenxPool must be >= existing totalClaimed when updating.
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
            // Adjust global allocation to reflect new pool size.
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

    /// @notice Activate or deactivate a raffle.
    function setRaffleActive(uint256 raffleId, bool active) external onlyOwner {
        Raffle storage raffle = _raffles[raffleId];
        require(raffle.totalTenxPool > 0, "RaffleVault: invalid raffle");
        raffle.active = active;
        emit RaffleConfigured(raffleId, raffle.seasonId, raffle.tier, raffle.merkleRoot, raffle.totalTenxPool, active);
    }

    /// @notice Get details of a raffle.
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

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, raffleId, tenxAmount));
        bool validProof = MerkleProof.verify(merkleProof, raffle.merkleRoot, leaf);
        require(validProof, "RaffleVault: invalid proof");

        require(raffle.totalClaimed + tenxAmount <= raffle.totalTenxPool, "RaffleVault: insufficient pool");

        _hasClaimed[raffleId][msg.sender] = true;
        raffle.totalClaimed += tenxAmount;
        _totalClaimedOverall += tenxAmount;

        emit RaffleClaimed(msg.sender, raffleId, tenxAmount);

        require(tenxToken.transfer(msg.sender, tenxAmount), "RaffleVault: transfer failed");
    }

    /// @notice Check whether a user has claimed a raffle.
    function hasClaimed(uint256 raffleId, address user) external view returns (bool) {
        return _hasClaimed[raffleId][user];
    }

    /// @notice Returns whether a claim would be valid and whether it was already claimed.
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

        bytes32 leaf = keccak256(abi.encodePacked(user, raffleId, tenxAmount));
        bool validProof = MerkleProof.verify(merkleProof, raffle.merkleRoot, leaf);
        return (validProof, _hasClaimed[raffleId][user]);
    }

    // =============================================================
    // Locking / TGE
    // =============================================================

    /// @notice Set the TGE timestamp. Can only be set once.
    function setTGETimestamp(uint256 tgeTimestamp) external onlyOwner {
        require(!_tgeSet, "RaffleVault: TGE already set");
        require(tgeTimestamp > block.timestamp, "RaffleVault: TGE must be in future");
        _tgeTimestamp = tgeTimestamp;
        _tgeSet = true;
        emit TGETimestampSet(tgeTimestamp);
    }

    /// @notice Enable or disable lock enforcement.
    function setLockEnforced(bool enforced) external onlyOwner {
        _lockEnforced = enforced;
        emit LockEnforcedUpdated(enforced);
    }

    /// @notice Returns whether claims are currently unlocked.
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
    function getUnlockTime() external view returns (uint256) {
        if (!_tgeSet) {
            return 0;
        }
        return _tgeTimestamp + 365 days;
    }

    /// @notice Returns the configured TGE timestamp and whether it has been set.
    function getTGETimestamp() external view returns (uint256 tgeTimestamp, bool tgeSet) {
        return (_tgeTimestamp, _tgeSet);
    }

    // =============================================================
    // Funding & Rescue
    // =============================================================

    /// @notice Current TENX balance held by the vault.
    function vaultBalance() public view returns (uint256) {
        return tenxToken.balanceOf(address(this));
    }

    /// @notice Returns total TENX allocated across all raffles.
    function totalPoolAllocated() external view returns (uint256) {
        return _totalPoolAllocated;
    }

    /// @notice Returns total TENX claimed across all raffles.
    function totalClaimedOverall() external view returns (uint256) {
        return _totalClaimedOverall;
    }

    /// @notice Rescue tokens mistakenly sent to the vault.
    /// @dev TENX withdrawals are limited to preserve unclaimed allocations.
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
