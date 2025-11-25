// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Prime10X Marketing Vault
/// @notice Holds TENX tokens for marketing campaigns and enforces a global time lock before users can claim.
contract Prime10XMarketingVault is Ownable, ReentrancyGuard {
    /// @dev Emitted when tokens are locked for a user for a specific season.
    event Locked(address indexed user, uint256 amount, uint256 indexed seasonId);

    /// @dev Emitted when a user claims unlocked tokens.
    event Claimed(address indexed user, uint256 amount);

    /// @dev Emitted when the TGE timestamp is set.
    event TGETimestampSet(uint256 tgeTimestamp);

    /// @dev Emitted when a distributor role is updated.
    event DistributorUpdated(address indexed account, bool isDistributor);

    IERC20 public immutable tenxToken;

    // Locking parameters
    uint256 public constant LOCK_DURATION = 365 days;
    uint256 public tgeTimestamp;
    bool public tgeSet;

    // Role management
    mapping(address => bool) private _distributors;

    // User balances
    mapping(address => uint256) private _totalLocked;
    mapping(address => uint256) private _totalClaimed;
    mapping(uint256 => uint256) private _seasonTotalLocked;
    mapping(address => mapping(uint256 => uint256)) private _lockedBySeason;

    // Tracks total locked tokens outstanding across all users.
    uint256 private _globalLocked;

    /// @param tenxToken_ Address of the TENX ERC-20 token.
    constructor(address tenxToken_) {
        require(tenxToken_ != address(0), "MarketingVault: invalid token");
        tenxToken = IERC20(tenxToken_);
    }

    // ------------------------------------------------------
    // Modifiers
    // ------------------------------------------------------

    modifier onlyOwnerOrDistributor() {
        require(owner() == _msgSender() || _distributors[_msgSender()], "MarketingVault: not authorized");
        _;
    }

    // ------------------------------------------------------
    // Admin functions
    // ------------------------------------------------------

    /// @notice Sets the TGE timestamp. Can only be called once and must be in the future.
    /// @param tgeTimestamp_ Timestamp for the Token Generation Event.
    function setTGETimestamp(uint256 tgeTimestamp_) external onlyOwner {
        require(!tgeSet, "MarketingVault: TGE already set");
        require(tgeTimestamp_ > block.timestamp, "MarketingVault: TGE must be in future");
        tgeTimestamp = tgeTimestamp_;
        tgeSet = true;
        emit TGETimestampSet(tgeTimestamp_);
    }

    /// @notice Updates distributor status for an account.
    /// @param account Address to update.
    /// @param isDistributor True to grant distributor role, false to revoke.
    function setDistributor(address account, bool isDistributor) external onlyOwner {
        require(account != address(0), "MarketingVault: invalid user");
        _distributors[account] = isDistributor;
        emit DistributorUpdated(account, isDistributor);
    }

    // ------------------------------------------------------
    // Allocation functions
    // ------------------------------------------------------

    /// @notice Allocates locked TENX tokens to a user for a given season.
    /// @param user Recipient of the locked tokens.
    /// @param amount Amount of TENX tokens to lock.
    /// @param seasonId Season identifier (must be > 0).
    function allocateLockedTokens(address user, uint256 amount, uint256 seasonId) external onlyOwnerOrDistributor {
        _allocate(user, amount, seasonId);
    }

    /// @notice Batch allocates locked TENX tokens to multiple users for a given season.
    /// @param users Array of recipient addresses.
    /// @param amounts Array of amounts corresponding to each user.
    /// @param seasonId Season identifier (must be > 0).
    function batchAllocateLockedTokens(address[] calldata users, uint256[] calldata amounts, uint256 seasonId) external onlyOwnerOrDistributor {
        require(users.length == amounts.length, "MarketingVault: length mismatch");
        for (uint256 i = 0; i < users.length; i++) {
            _allocate(users[i], amounts[i], seasonId);
        }
    }

    /// @dev Internal allocation logic shared by single and batch allocation.
    function _allocate(address user, uint256 amount, uint256 seasonId) internal {
        require(user != address(0), "MarketingVault: invalid user");
        require(amount > 0, "MarketingVault: invalid amount");
        require(seasonId > 0, "MarketingVault: invalid season");

        _totalLocked[user] += amount;
        _lockedBySeason[user][seasonId] += amount;
        _seasonTotalLocked[seasonId] += amount;
        _globalLocked += amount;

        emit Locked(user, amount, seasonId);
    }

    // ------------------------------------------------------
    // Claim functions
    // ------------------------------------------------------

    /// @notice Claims unlocked tokens for the caller after the lock period has passed.
    function claim() external nonReentrant {
        _claimTo(_msgSender());
    }

    /// @notice Claims unlocked tokens for a user. Callable only by the owner.
    /// @param user Address to claim for.
    function claimFor(address user) external nonReentrant onlyOwner {
        _claimTo(user);
    }

    /// @dev Internal claim logic used by both claim and claimFor.
    function _claimTo(address user) internal {
        require(tgeSet, "MarketingVault: TGE not set");
        require(isUnlocked(), "MarketingVault: not unlocked yet");
        uint256 claimable = _totalLocked[user];
        require(claimable > 0, "MarketingVault: nothing to claim");

        _totalLocked[user] = 0;
        _totalClaimed[user] += claimable;
        _globalLocked -= claimable;

        require(tenxToken.transfer(user, claimable), "MarketingVault: transfer failed");
        emit Claimed(user, claimable);
    }

    // ------------------------------------------------------
    // View functions
    // ------------------------------------------------------

    /// @notice Returns the total locked (unclaimed) balance for a user.
    function totalLockedOf(address user) external view returns (uint256) {
        return _totalLocked[user];
    }

    /// @notice Returns the total claimed balance for a user.
    function totalClaimedOf(address user) external view returns (uint256) {
        return _totalClaimed[user];
    }

    /// @notice Returns the locked balance for a user for a specific season.
    function lockedBySeason(address user, uint256 seasonId) external view returns (uint256) {
        return _lockedBySeason[user][seasonId];
    }

    /// @notice Returns the total locked amount for a season across all users.
    function seasonTotalLocked(uint256 seasonId) external view returns (uint256) {
        return _seasonTotalLocked[seasonId];
    }

    /// @notice Returns the unlock timestamp derived from TGE.
    function getUnlockTime() external view returns (uint256) {
        return tgeSet ? tgeTimestamp + LOCK_DURATION : 0;
    }

    /// @notice Returns true if the lock period has elapsed and TGE is set.
    function isUnlocked() public view returns (bool) {
        return tgeSet && block.timestamp >= tgeTimestamp + LOCK_DURATION;
    }

    /// @notice Returns the TENX token balance held by the vault.
    function vaultBalance() public view returns (uint256) {
        return tenxToken.balanceOf(address(this));
    }

    // ------------------------------------------------------
    // Rescue functions
    // ------------------------------------------------------

    /// @notice Allows the owner to rescue tokens mistakenly sent to the contract.
    /// TENX tokens can only be rescued if sufficient balance remains to cover outstanding locked amounts.
    /// @param token Address of the token to rescue.
    /// @param to Recipient of the rescued tokens.
    /// @param amount Amount of tokens to rescue.
    function rescueTokens(address token, address to, uint256 amount) external onlyOwner {
        require(to != address(0), "MarketingVault: invalid user");
        IERC20 erc20 = IERC20(token);

        if (token == address(tenxToken)) {
            uint256 newBalance = erc20.balanceOf(address(this)) - amount;
            require(newBalance >= _globalLocked, "MarketingVault: insufficient TENX balance");
        }

        require(erc20.transfer(to, amount), "MarketingVault: rescue failed");
    }
}

