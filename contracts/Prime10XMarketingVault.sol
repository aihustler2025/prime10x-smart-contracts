// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Prime10X Marketing Vault
/// @author Prime10X Team
/// @notice Holds TENX tokens for marketing campaigns and enforces a configurable claim-enable date.
/// @dev Tokens are allocated per-user per-season and become claimable after the claim enable date.
///      The owner or designated distributors can allocate tokens. The owner can set the claim enable date
///      and an emergency admin (multi-sig) can update it if needed. The TENX token address can be set
///      after deployment via a one-shot setter, allowing the vault to deploy before the token exists.
contract Prime10XMarketingVault is Ownable2Step, ReentrancyGuard {
    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------

    /// @notice Emitted when tokens are locked for a user for a specific season.
    /// @param user The recipient of the locked tokens.
    /// @param amount The amount of TENX tokens locked.
    /// @param seasonId The season identifier for this allocation.
    event Locked(address indexed user, uint256 amount, uint256 indexed seasonId);

    /// @notice Emitted when a user claims unlocked tokens.
    /// @param user The address that received the claimed tokens.
    /// @param amount The amount of TENX tokens claimed.
    event Claimed(address indexed user, uint256 amount);

    /// @notice Emitted when the claim enable date is set or updated.
    /// @param claimEnableDate The configured claim enable timestamp.
    event ClaimEnableDateSet(uint256 claimEnableDate);

    /// @notice Emitted when a distributor role is updated.
    /// @param account The address whose distributor status changed.
    /// @param isDistributor Whether the account is now a distributor.
    event DistributorUpdated(address indexed account, bool isDistributor);

    /// @notice Emitted when the emergency admin is updated.
    /// @param admin The new emergency admin address.
    event EmergencyAdminUpdated(address admin);

    /// @notice Emitted when the TENX token address is set.
    /// @param token The TENX token address.
    event TokenAddressSet(address token);

    /// @notice Emitted when TENX tokens are deposited into the vault.
    /// @param depositor The address that deposited the tokens.
    /// @param amount The amount of TENX tokens deposited.
    event TokensDeposited(address indexed depositor, uint256 amount);

    // ------------------------------------------------------------------
    // State variables
    // ------------------------------------------------------------------

    /// @notice The TENX ERC-20 token managed by this vault.
    IERC20 public tenxToken;

    /// @notice Timestamp after which claims are allowed. Zero until set.
    uint256 public claimEnableDate;

    /// @notice Whether the claim enable date has been set.
    bool public claimEnableDateSet;

    /// @dev The emergency admin address (e.g. multi-sig) that can update the claim date.
    address private _emergencyAdmin;

    /// @dev Mapping of addresses to their distributor status.
    mapping(address => bool) private _distributors;

    /// @dev Total locked (unclaimed) balance per user.
    mapping(address => uint256) private _totalLocked;

    /// @dev Total claimed balance per user.
    mapping(address => uint256) private _totalClaimed;

    /// @dev Total locked amount per season across all users.
    mapping(uint256 => uint256) private _seasonTotalLocked;

    /// @dev Locked amount per user per season.
    mapping(address => mapping(uint256 => uint256)) private _lockedBySeason;

    /// @dev Sum of all outstanding locked tokens across all users.
    uint256 private _globalLocked;

    // ------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------

    /// @notice Deploys the marketing vault, optionally bound to a TENX token.
    /// @dev Pass address(0) if the TENX token is not yet deployed; set it later via setTokenAddress().
    /// @param tenxToken_ Address of the TENX ERC-20 token contract, or address(0).
    constructor(address tenxToken_) Ownable(msg.sender) {
        tenxToken = IERC20(tenxToken_);
    }

    // ------------------------------------------------------------------
    // Modifiers
    // ------------------------------------------------------------------

    /// @dev Restricts access to the owner or an approved distributor.
    modifier onlyOwnerOrDistributor() {
        require(owner() == _msgSender() || _distributors[_msgSender()], "MarketingVault: not authorized");
        _;
    }

    // ------------------------------------------------------------------
    // Admin functions
    // ------------------------------------------------------------------

    /// @notice Sets or updates the claim enable date.
    /// @dev Can be called multiple times to adjust the claim date as timelines shift.
    /// @param claimEnableDate_ Timestamp after which claims are allowed (must be > 0).
    function setClaimEnableDate(uint256 claimEnableDate_) external onlyOwner {
        require(claimEnableDate_ > 0, "MarketingVault: invalid date");
        claimEnableDate = claimEnableDate_;
        claimEnableDateSet = true;
        emit ClaimEnableDateSet(claimEnableDate_);
    }

    /// @notice Allows the emergency admin to update the claim enable date.
    /// @dev Only callable by the emergency admin address (e.g. multi-sig wallet).
    /// @param claimEnableDate_ New claim enable timestamp (must be > 0).
    function emergencyUpdateClaimDate(uint256 claimEnableDate_) external {
        require(msg.sender == _emergencyAdmin, "MarketingVault: not emergency admin");
        require(claimEnableDate_ > 0, "MarketingVault: invalid date");
        claimEnableDate = claimEnableDate_;
        claimEnableDateSet = true;
        emit ClaimEnableDateSet(claimEnableDate_);
    }

    /// @notice Sets the emergency admin address.
    /// @dev Only callable by the owner. The emergency admin can update the claim date.
    /// @param admin The new emergency admin address.
    function setEmergencyAdmin(address admin) external onlyOwner {
        _emergencyAdmin = admin;
        emit EmergencyAdminUpdated(admin);
    }

    /// @notice Sets the TENX token address. Can only be called once (one-shot setter).
    /// @dev Allows the vault to be deployed before the TENX token exists.
    /// @param token The TENX token address (must not be address(0)).
    function setTokenAddress(address token) external onlyOwner {
        require(address(tenxToken) == address(0), "MarketingVault: token already set");
        require(token != address(0), "MarketingVault: invalid token");
        tenxToken = IERC20(token);
        emit TokenAddressSet(token);
    }

    /// @notice Updates distributor status for an account.
    /// @param account Address to update.
    /// @param isDistributor True to grant distributor role, false to revoke.
    function setDistributor(address account, bool isDistributor) external onlyOwner {
        require(account != address(0), "MarketingVault: invalid user");
        _distributors[account] = isDistributor;
        emit DistributorUpdated(account, isDistributor);
    }

    // ------------------------------------------------------------------
    // Deposit functions
    // ------------------------------------------------------------------

    /// @notice Deposits TENX tokens into the vault.
    /// @dev Caller must have approved this contract to spend at least `amount` TENX tokens.
    ///      Requires that the token address has been set.
    /// @param amount Amount of TENX tokens to deposit.
    function depositTokens(uint256 amount) external {
        require(address(tenxToken) != address(0), "MarketingVault: token not set");
        require(amount > 0, "MarketingVault: invalid amount");
        require(tenxToken.transferFrom(_msgSender(), address(this), amount), "MarketingVault: deposit failed");
        emit TokensDeposited(_msgSender(), amount);
    }

    // ------------------------------------------------------------------
    // Allocation functions
    // ------------------------------------------------------------------

    /// @notice Allocates locked TENX tokens to a user for a given season.
    /// @dev Caller must be the owner or an approved distributor.
    /// @param user Recipient of the locked tokens.
    /// @param amount Amount of TENX tokens to lock.
    /// @param seasonId Season identifier (must be > 0).
    function allocateLockedTokens(address user, uint256 amount, uint256 seasonId) external onlyOwnerOrDistributor {
        _allocate(user, amount, seasonId);
    }

    /// @notice Batch allocates locked TENX tokens to multiple users for a given season.
    /// @dev Arrays must be equal length. Caller must be the owner or an approved distributor.
    /// @param users Array of recipient addresses.
    /// @param amounts Array of amounts corresponding to each user.
    /// @param seasonId Season identifier (must be > 0).
    function batchAllocateLockedTokens(address[] calldata users, uint256[] calldata amounts, uint256 seasonId)
        external
        onlyOwnerOrDistributor
    {
        require(users.length == amounts.length, "MarketingVault: length mismatch");
        for (uint256 i = 0; i < users.length; i++) {
            _allocate(users[i], amounts[i], seasonId);
        }
    }

    /// @dev Internal allocation logic shared by single and batch allocation.
    /// @param user Recipient of the locked tokens.
    /// @param amount Amount of TENX tokens to lock.
    /// @param seasonId Season identifier (must be > 0).
    function _allocate(address user, uint256 amount, uint256 seasonId) internal {
        require(address(tenxToken) != address(0), "MarketingVault: token not set");
        require(user != address(0), "MarketingVault: invalid user");
        require(amount > 0, "MarketingVault: invalid amount");
        require(seasonId > 0, "MarketingVault: invalid season");
        require(_globalLocked + amount <= tenxToken.balanceOf(address(this)), "MarketingVault: vault underfunded");

        _totalLocked[user] += amount;
        _lockedBySeason[user][seasonId] += amount;
        _seasonTotalLocked[seasonId] += amount;
        _globalLocked += amount;

        emit Locked(user, amount, seasonId);
    }

    // ------------------------------------------------------------------
    // Claim functions
    // ------------------------------------------------------------------

    /// @notice Claims all unlocked tokens for the caller after the claim enable date has passed.
    /// @custom:security Protected by ReentrancyGuard.
    function claim() external nonReentrant {
        _claimTo(_msgSender());
    }

    /// @notice Claims unlocked tokens on behalf of a user. Only callable by the owner.
    /// @param user Address to claim for.
    /// @custom:security Owner-only. Useful for batch admin operations.
    function claimFor(address user) external nonReentrant onlyOwner {
        _claimTo(user);
    }

    /// @dev Internal claim logic used by both `claim` and `claimFor`.
    /// @param user Address whose locked tokens are being claimed.
    function _claimTo(address user) internal {
        require(isClaimEnabled(), "MarketingVault: claims not enabled");
        uint256 claimable = _totalLocked[user];
        require(claimable > 0, "MarketingVault: nothing to claim");

        _totalLocked[user] = 0;
        _totalClaimed[user] += claimable;
        _globalLocked -= claimable;

        require(tenxToken.transfer(user, claimable), "MarketingVault: transfer failed");
        emit Claimed(user, claimable);
    }

    // ------------------------------------------------------------------
    // View functions
    // ------------------------------------------------------------------

    /// @notice Returns the total locked (unclaimed) balance for a user.
    /// @param user Address to query.
    /// @return The amount of TENX tokens still locked for the user.
    function totalLockedOf(address user) external view returns (uint256) {
        return _totalLocked[user];
    }

    /// @notice Returns the total claimed balance for a user.
    /// @param user Address to query.
    /// @return The cumulative amount of TENX tokens the user has claimed.
    function totalClaimedOf(address user) external view returns (uint256) {
        return _totalClaimed[user];
    }

    /// @notice Returns the locked balance for a user for a specific season.
    /// @param user Address to query.
    /// @param seasonId Season identifier to query.
    /// @return The amount of TENX tokens locked for the user in the given season.
    function lockedBySeason(address user, uint256 seasonId) external view returns (uint256) {
        return _lockedBySeason[user][seasonId];
    }

    /// @notice Returns the total locked amount for a season across all users.
    /// @param seasonId Season identifier to query.
    /// @return The aggregate TENX tokens locked for the given season.
    function seasonTotalLocked(uint256 seasonId) external view returns (uint256) {
        return _seasonTotalLocked[seasonId];
    }

    /// @notice Returns true if claims are currently allowed.
    /// @dev Returns true if claim enable date is set and current time has passed it.
    /// @return Whether claims are currently enabled.
    function isClaimEnabled() public view returns (bool) {
        return claimEnableDateSet && block.timestamp >= claimEnableDate;
    }

    /// @notice Returns the TENX token balance held by the vault.
    /// @return The current TENX balance of this contract.
    function vaultBalance() public view returns (uint256) {
        require(address(tenxToken) != address(0), "MarketingVault: token not set");
        return tenxToken.balanceOf(address(this));
    }

    // ------------------------------------------------------------------
    // Rescue functions
    // ------------------------------------------------------------------

    /// @notice Allows the owner to rescue tokens mistakenly sent to the contract.
    /// @dev TENX tokens can only be rescued if sufficient balance remains to cover outstanding locked amounts.
    /// @param token Address of the ERC-20 token to rescue.
    /// @param to Recipient of the rescued tokens.
    /// @param amount Amount of tokens to rescue.
    /// @custom:security Ensures TENX rescue never dips below committed allocations.
    function rescueTokens(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0), "MarketingVault: invalid user");
        IERC20 erc20 = IERC20(token);

        if (address(tenxToken) != address(0) && token == address(tenxToken)) {
            uint256 balance = erc20.balanceOf(address(this));
            require(balance >= amount, "MarketingVault: insufficient balance");
            require(balance - amount >= _globalLocked, "MarketingVault: insufficient TENX balance");
        }

        require(erc20.transfer(to, amount), "MarketingVault: rescue failed");
    }
}
