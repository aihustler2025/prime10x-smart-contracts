// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/// @title Prime10X Badge Soulbound Token
/// @author Prime10X Team
/// @notice Non-transferable ERC721 token representing Prime10X seasonal achievement badges.
/// @dev Badges are minted by the contract owner after off-chain eligibility checks.
///      Each wallet can hold at most one badge per season. Transfers are blocked (soulbound).
contract Prime10XBadgeSBT is ERC721, Ownable2Step {
    // ------------------------------------------------------------------
    // Constants
    // ------------------------------------------------------------------

    /// @dev Minimum valid badge type identifier.
    uint256 private constant BADGE_TYPE_MIN = 0;

    /// @dev Maximum valid badge type identifier.
    uint256 private constant BADGE_TYPE_MAX = 5;

    // ------------------------------------------------------------------
    // Storage
    // ------------------------------------------------------------------

    /// @dev Counter for the next token ID to be minted (starts at 1).
    uint256 private _nextTokenId;

    /// @dev Number of currently active (non-revoked) badges.
    uint256 private _totalSupply;

    /// @dev Tracks the tokenId owned by an address for a specific season.
    mapping(address => mapping(uint256 => uint256)) private _seasonBadgeOf;

    /// @dev Tracks the badge type of a tokenId.
    mapping(uint256 => uint256) private _badgeTypeOf;

    /// @dev Tracks the season of a tokenId.
    mapping(uint256 => uint256) private _seasonOf;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------

    /// @notice Emitted when a new badge is minted.
    /// @param to The recipient of the badge.
    /// @param tokenId The minted token ID.
    /// @param season The season identifier.
    /// @param badgeType The badge type (0-5).
    event BadgeMinted(address indexed to, uint256 indexed tokenId, uint256 season, uint256 badgeType);

    /// @notice Emitted when a badge is revoked (burned).
    /// @param from The address whose badge was revoked.
    /// @param tokenId The revoked token ID.
    event BadgeRevoked(address indexed from, uint256 indexed tokenId);

    // ------------------------------------------------------------------
    // Errors
    // ------------------------------------------------------------------

    /// @dev Thrown when a transfer, approval, or other non-mint/burn operation is attempted.
    error Soulbound();

    /// @dev Thrown when the badge type is outside the valid range [0, 5].
    error InvalidBadgeType();

    /// @dev Thrown when the season identifier is zero.
    error InvalidSeason();

    /// @dev Thrown when the wallet already has a badge for the given season.
    error BadgeAlreadyAssigned();

    // ------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------

    /// @notice Deploys the badge contract with fixed name and symbol.
    constructor() ERC721("Prime10X Badge", "P10X-SBT") Ownable(msg.sender) {}

    // ------------------------------------------------------------------
    // External functions
    // ------------------------------------------------------------------

    /// @notice Mint a badge to a wallet for a given season and badge type.
    /// @dev Only callable by the contract owner after off-chain eligibility checks.
    ///      Each wallet can only hold one badge per season.
    /// @param to Recipient wallet address.
    /// @param season Season identifier (must be non-zero).
    /// @param badgeType Badge type (0-5).
    /// @custom:security Owner-only. Enforces one-badge-per-season-per-wallet.
    function mintBadge(address to, uint256 season, uint256 badgeType) external onlyOwner {
        if (season == 0) revert InvalidSeason();
        if (badgeType < BADGE_TYPE_MIN || badgeType > BADGE_TYPE_MAX) revert InvalidBadgeType();
        if (_seasonBadgeOf[to][season] != 0) revert BadgeAlreadyAssigned();

        uint256 newTokenId = ++_nextTokenId;

        _badgeTypeOf[newTokenId] = badgeType;
        _seasonOf[newTokenId] = season;
        _seasonBadgeOf[to][season] = newTokenId;

        _safeMint(to, newTokenId);
        unchecked {
            _totalSupply += 1;
        }

        emit BadgeMinted(to, newTokenId, season, badgeType);
    }

    /// @notice Revoke (burn) a badge token.
    /// @dev Only callable by the contract owner. Clears all metadata mappings.
    /// @param tokenId Token ID to revoke.
    function revokeBadge(uint256 tokenId) external onlyOwner {
        address holder = ownerOf(tokenId);
        uint256 season = _seasonOf[tokenId];

        _burn(tokenId);

        delete _seasonBadgeOf[holder][season];
        delete _badgeTypeOf[tokenId];
        delete _seasonOf[tokenId];

        unchecked {
            _totalSupply -= 1;
        }

        emit BadgeRevoked(holder, tokenId);
    }

    /// @notice Returns the tokenId owned by `user` for `season`, or 0 if none.
    /// @param user Address to query.
    /// @param season Season identifier to query.
    /// @return The token ID, or 0 if the user has no badge for that season.
    function walletOf(address user, uint256 season) external view returns (uint256) {
        return _seasonBadgeOf[user][season];
    }

    /// @notice Total active supply (minted minus revoked tokens).
    /// @return The number of currently active badges.
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    // ------------------------------------------------------------------
    // Metadata
    // ------------------------------------------------------------------

    /// @notice Returns the metadata URI for a given token.
    /// @dev Format: `https://prime10x.com/badges/season/{season}/{badgeType}.json`
    /// @param tokenId The token ID to query.
    /// @return The full metadata URI string.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        uint256 season = _seasonOf[tokenId];
        uint256 badgeType = _badgeTypeOf[tokenId];

        return string(
            abi.encodePacked(
                "https://prime10x.com/badges/season/",
                Strings.toString(season),
                "/",
                Strings.toString(badgeType),
                ".json"
            )
        );
    }

    // ------------------------------------------------------------------
    // Soulbound enforcement
    // ------------------------------------------------------------------

    /// @dev Blocks all transfers except minting (from == address(0)) and burning (to == address(0)).
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) revert Soulbound();
        return super._update(to, tokenId, auth);
    }

    /// @dev Reverts — badges cannot be approved for transfer.
    function approve(address, uint256) public pure override {
        revert Soulbound();
    }

    /// @dev Reverts — badges cannot be approved for transfer.
    function setApprovalForAll(address, bool) public pure override {
        revert Soulbound();
    }

    /// @dev Reverts — badges cannot be transferred.
    function transferFrom(address, address, uint256) public pure override {
        revert Soulbound();
    }

    /// @dev Reverts — badges cannot be transferred.
    function safeTransferFrom(address, address, uint256, bytes memory) public pure override {
        revert Soulbound();
    }
}
