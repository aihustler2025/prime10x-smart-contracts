// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Prime10X Reward Voucher NFT (Soulbound)
/// @author Prime10X Team
/// @notice Represents a claim to receive locked TENX tokens for a given season.
/// @dev Vouchers are non-transferable (soulbound) and can be redeemed exactly once, but only after
///      the claim enable date has passed. The owner can update the claim date as timelines shift.
///      Implements ERC721Enumerable for on-chain enumeration of a user's vouchers.
contract Prime10XRewardVoucher is ERC721Enumerable, Ownable2Step, ReentrancyGuard {
    using Strings for uint256;

    // ------------------------------------------------------------------
    // Storage
    // ------------------------------------------------------------------

    /// @dev Counter for the next token ID to be minted (starts at 1).
    uint256 private _nextTokenId;

    /// @dev TENX amount associated with each voucher token.
    mapping(uint256 => uint256) private _tenxAmount;

    /// @dev Season ID associated with each voucher token.
    mapping(uint256 => uint256) private _seasonId;

    /// @dev Whether a voucher has been redeemed.
    mapping(uint256 => bool) private _redeemed;

    /// @dev Base URI for token metadata.
    string private _baseTokenURI;

    /// @notice Timestamp after which vouchers can be redeemed. Zero until set.
    uint256 public claimEnableDate;

    /// @notice Whether the claim enable date has been set.
    bool public claimEnableDateSet;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------

    /// @notice Emitted when a new voucher is minted.
    /// @param to The recipient of the voucher.
    /// @param tokenId The minted token ID.
    /// @param tenxAmount The TENX amount the voucher represents.
    /// @param seasonId The season identifier.
    event VoucherMinted(address indexed to, uint256 indexed tokenId, uint256 tenxAmount, uint256 seasonId);

    /// @notice Emitted when a voucher is redeemed by its holder.
    /// @param redeemer The address that redeemed the voucher.
    /// @param tokenId The redeemed token ID.
    /// @param tenxAmount The TENX amount that was represented.
    /// @param seasonId The season identifier.
    event VoucherRedeemed(address indexed redeemer, uint256 indexed tokenId, uint256 tenxAmount, uint256 seasonId);

    /// @notice Emitted when a voucher is revoked (burned) by the owner.
    /// @param from The address whose voucher was revoked.
    /// @param tokenId The revoked token ID.
    event VoucherRevoked(address indexed from, uint256 indexed tokenId);

    /// @notice Emitted when the base URI is updated.
    /// @param newBaseURI The new base URI string.
    event BaseURIUpdated(string newBaseURI);

    /// @notice Emitted when the claim enable date is set or updated.
    /// @param claimEnableDate The new claim enable timestamp.
    event ClaimEnableDateSet(uint256 claimEnableDate);

    // ------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------

    /// @notice Deploys the reward voucher contract with the given name and symbol.
    /// @param name_ The ERC721 token name.
    /// @param symbol_ The ERC721 token symbol.
    constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) Ownable(msg.sender) {}

    // ------------------------------------------------------------------
    // Admin functions
    // ------------------------------------------------------------------

    /// @notice Set a new base URI for token metadata.
    /// @param newBaseURI The new base URI to use for token metadata.
    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        _baseTokenURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }

    /// @notice Sets or updates the claim enable date.
    /// @dev Can be called multiple times to adjust the date as timelines shift.
    ///      Voucher redemptions are blocked until this date passes.
    /// @param claimEnableDate_ Timestamp after which vouchers can be redeemed.
    function setClaimEnableDate(uint256 claimEnableDate_) external onlyOwner {
        require(claimEnableDate_ > 0, "RewardVoucher: invalid date");
        claimEnableDate = claimEnableDate_;
        claimEnableDateSet = true;
        emit ClaimEnableDateSet(claimEnableDate_);
    }

    // ------------------------------------------------------------------
    // Voucher lifecycle
    // ------------------------------------------------------------------

    /// @notice Mint a new voucher NFT to a recipient.
    /// @dev Only callable by the contract owner.
    /// @param to Recipient address (must not be zero).
    /// @param tenxAmount Amount of TENX (18 decimals) the voucher represents.
    /// @param seasonId Season identifier (must be > 0).
    function mintVoucher(address to, uint256 tenxAmount, uint256 seasonId) external onlyOwner {
        require(to != address(0), "Invalid recipient");
        require(tenxAmount > 0, "Invalid amount");
        require(seasonId > 0, "Invalid season");

        uint256 tokenId = ++_nextTokenId;

        _tenxAmount[tokenId] = tenxAmount;
        _seasonId[tokenId] = seasonId;

        _safeMint(to, tokenId);

        emit VoucherMinted(to, tokenId, tenxAmount, seasonId);
    }

    /// @notice Redeem a voucher. Burns the voucher and marks it as redeemed.
    /// @dev Only the voucher holder can redeem, and only after the claim enable date has passed.
    ///      The redemption flag is preserved for historical queries.
    /// @param tokenId ID of the voucher to redeem.
    /// @custom:security Protected by ReentrancyGuard. Only callable by the token owner after claim date.
    function redeemVoucher(uint256 tokenId) external nonReentrant {
        require(_ownerOf(tokenId) != address(0), "Nonexistent token");
        require(ownerOf(tokenId) == msg.sender, "Not voucher owner");
        require(!_redeemed[tokenId], "Already redeemed");
        require(isRedeemable(), "RewardVoucher: claims not enabled");

        _redeemed[tokenId] = true;
        uint256 tenxAmount = _tenxAmount[tokenId];
        uint256 seasonId = _seasonId[tokenId];

        _burn(tokenId);

        emit VoucherRedeemed(msg.sender, tokenId, tenxAmount, seasonId);
    }

    /// @notice Revoke (burn) a voucher. Only callable by the contract owner.
    /// @dev Cannot revoke an already-redeemed voucher.
    /// @param tokenId ID of the voucher to revoke.
    function revokeVoucher(uint256 tokenId) external onlyOwner {
        require(_ownerOf(tokenId) != address(0), "Nonexistent token");
        require(!_redeemed[tokenId], "Already redeemed");

        address voucherOwner = ownerOf(tokenId);
        _burn(tokenId);

        emit VoucherRevoked(voucherOwner, tokenId);
    }

    // ------------------------------------------------------------------
    // View functions
    // ------------------------------------------------------------------

    /// @notice Get voucher metadata for a specific token.
    /// @param tokenId ID of the voucher.
    /// @return tenxAmount The TENX amount the voucher represents.
    /// @return seasonId The season identifier.
    /// @return redeemed Whether the voucher has been redeemed.
    function getVoucherInfo(uint256 tokenId) external view returns (uint256 tenxAmount, uint256 seasonId, bool redeemed) {
        require(_ownerOf(tokenId) != address(0), "Nonexistent token");
        return (_tenxAmount[tokenId], _seasonId[tokenId], _redeemed[tokenId]);
    }

    /// @notice List all voucher token IDs owned by a user.
    /// @param user Address to query.
    /// @return tokenIds Array of token IDs owned by the user.
    function vouchersOf(address user) external view returns (uint256[] memory tokenIds) {
        uint256 balance = balanceOf(user);
        tokenIds = new uint256[](balance);
        for (uint256 i = 0; i < balance; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(user, i);
        }
    }

    /// @notice Returns whether vouchers can currently be redeemed.
    /// @dev True when claim enable date is set and the current time has passed it.
    /// @return Whether voucher redemptions are currently allowed.
    function isRedeemable() public view returns (bool) {
        return claimEnableDateSet && block.timestamp >= claimEnableDate;
    }

    // ------------------------------------------------------------------
    // Soulbound enforcement
    // ------------------------------------------------------------------

    /// @dev Blocks all transfers except minting (from == address(0)) and burning (to == address(0)).
    function _update(address to, uint256 tokenId, address auth) internal override(ERC721Enumerable) returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) {
            revert("Voucher is soulbound");
        }
        return super._update(to, tokenId, auth);
    }

    /// @dev Required override for ERC721Enumerable.
    function _increaseBalance(address account, uint128 value) internal override(ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    /// @dev Reverts — vouchers cannot be approved for transfer.
    function approve(address, uint256) public pure override(ERC721, IERC721) {
        revert("Voucher is soulbound");
    }

    /// @dev Reverts — vouchers cannot be approved for transfer.
    function setApprovalForAll(address, bool) public pure override(ERC721, IERC721) {
        revert("Voucher is soulbound");
    }

    /// @dev Reverts — vouchers cannot be transferred.
    function transferFrom(address, address, uint256) public pure override(ERC721, IERC721) {
        revert("Voucher is soulbound");
    }

    /// @dev Reverts — vouchers cannot be transferred.
    function safeTransferFrom(address, address, uint256, bytes memory) public pure override(ERC721, IERC721) {
        revert("Voucher is soulbound");
    }

    // ------------------------------------------------------------------
    // Metadata
    // ------------------------------------------------------------------

    /// @dev Returns the base URI for computing {tokenURI}.
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    /// @notice Returns the metadata URI for a given token.
    /// @dev Format: `{baseURI}/{seasonId}/{tokenId}.json`. Returns empty string if no base URI is set.
    /// @param tokenId The token ID to query.
    /// @return The full metadata URI string, or empty if no base URI is configured.
    function tokenURI(uint256 tokenId) public view override(ERC721) returns (string memory) {
        _requireOwned(tokenId);
        string memory base = _baseURI();
        uint256 seasonId = _seasonId[tokenId];
        if (bytes(base).length == 0) {
            return "";
        }
        return string(abi.encodePacked(base, "/", seasonId.toString(), "/", tokenId.toString(), ".json"));
    }

    /// @dev See {IERC165-supportsInterface}.
    function supportsInterface(bytes4 interfaceId) public view override(ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
