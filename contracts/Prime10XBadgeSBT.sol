// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title Prime10X Badge Soulbound Token for Season Achievements
 * @notice Non-transferable ERC721 token representing Prime10X seasonal badges.
 *         Badges are minted by the contract owner after off-chain eligibility checks.
 */
contract Prime10XBadgeSBT is ERC721, Ownable {
    using Counters for Counters.Counter;

    // ---------------------------------------------------------------------
    // Constants
    // ---------------------------------------------------------------------
    uint256 private constant BADGE_TYPE_MIN = 0;
    uint256 private constant BADGE_TYPE_MAX = 5;

    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------
    Counters.Counter private _tokenIdTracker;
    uint256 private _totalSupply;

    // Tracks tokenId owned by an address for a specific season (season => tokenId)
    mapping(address => mapping(uint256 => uint256)) private _seasonBadgeOf;

    // Tracks the badge type of a tokenId
    mapping(uint256 => uint256) private _badgeTypeOf;

    // Tracks the season of a tokenId
    mapping(uint256 => uint256) private _seasonOf;

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------
    event BadgeMinted(address indexed to, uint256 indexed tokenId, uint256 season, uint256 badgeType);
    event BadgeRevoked(address indexed from, uint256 indexed tokenId);

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------
    error Soulbound();
    error InvalidBadgeType();
    error InvalidSeason();
    error BadgeAlreadyAssigned();

    constructor() ERC721("Prime10X Badge", "P10X-SBT") {}

    // ---------------------------------------------------------------------
    // External functions
    // ---------------------------------------------------------------------

    /**
     * @notice Mint a badge to a wallet for a given season and badge type.
     * @dev Only callable by the contract owner after off-chain eligibility checks.
     * @param to Recipient wallet address.
     * @param season Season identifier (must be non-zero).
     * @param badgeType Badge type (0-5 for Season 1).
     */
    function mintBadge(address to, uint256 season, uint256 badgeType) external onlyOwner {
        if (season == 0) revert InvalidSeason();
        if (badgeType < BADGE_TYPE_MIN || badgeType > BADGE_TYPE_MAX) revert InvalidBadgeType();
        if (_seasonBadgeOf[to][season] != 0) revert BadgeAlreadyAssigned();

        _tokenIdTracker.increment();
        uint256 newTokenId = _tokenIdTracker.current();

        _badgeTypeOf[newTokenId] = badgeType;
        _seasonOf[newTokenId] = season;
        _seasonBadgeOf[to][season] = newTokenId;

        _safeMint(to, newTokenId);
        unchecked {
            _totalSupply += 1;
        }

        emit BadgeMinted(to, newTokenId, season, badgeType);
    }

    /**
     * @notice Revoke (burn) a badge token.
     * @dev Only callable by the contract owner.
     * @param tokenId Token ID to revoke.
     */
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

    /**
     * @notice Returns the tokenId owned by `user` for `season`, or 0 if none.
     */
    function walletOf(address user, uint256 season) external view returns (uint256) {
        return _seasonBadgeOf[user][season];
    }

    /**
     * @notice Total active supply (minted minus revoked tokens).
     */
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    // ---------------------------------------------------------------------
    // Metadata
    // ---------------------------------------------------------------------
    /**
     * @inheritdoc ERC721
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireMinted(tokenId);
        uint256 season = _seasonOf[tokenId];
        uint256 badgeType = _badgeTypeOf[tokenId];

        // Base URI: https://prime10x.com/badges/season/{season}/{badgeType}.json
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

    // ---------------------------------------------------------------------
    // Soulbound enforcement
    // ---------------------------------------------------------------------

    /**
     * @dev Blocks all transfers except minting (from == 0) and burning (to == 0).
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override {
        if (from != address(0) && to != address(0)) revert Soulbound();
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function approve(address, uint256) public pure override {
        revert Soulbound();
    }

    function setApprovalForAll(address, bool) public pure override {
        revert Soulbound();
    }

    function transferFrom(address, address, uint256) public pure override {
        revert Soulbound();
    }

    function safeTransferFrom(address, address, uint256) public pure override {
        revert Soulbound();
    }

    function safeTransferFrom(address, address, uint256, bytes memory) public pure override {
        revert Soulbound();
    }
}
