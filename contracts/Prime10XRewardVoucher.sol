// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title Prime10X Reward Voucher NFT (Soulbound)
/// @notice Represents a claim to receive locked TENX tokens for a given season.
/// @dev Vouchers are non-transferable and can be redeemed exactly once.
contract Prime10XRewardVoucher is ERC721Enumerable, Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;
    using Strings for uint256;

    Counters.Counter private _tokenIdTracker;

    mapping(uint256 => uint256) private _tenxAmount;
    mapping(uint256 => uint256) private _seasonId;
    mapping(uint256 => bool) private _redeemed;

    string private _baseTokenURI;

    event VoucherMinted(address indexed to, uint256 indexed tokenId, uint256 tenxAmount, uint256 seasonId);
    event VoucherRedeemed(address indexed redeemer, uint256 indexed tokenId, uint256 tenxAmount, uint256 seasonId);
    event VoucherRevoked(address indexed from, uint256 indexed tokenId);
    event BaseURIUpdated(string newBaseURI);

    constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) Ownable(msg.sender) {}

    /**
     * @notice Set a new base URI for token metadata.
     * @param newBaseURI The new base URI to use for token metadata.
     */
    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        _baseTokenURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }

    /**
     * @notice Mint a new voucher NFT to a recipient.
     * @param to Recipient address.
     * @param tenxAmount Amount of TENX (18 decimals) the voucher represents.
     * @param seasonId Season identifier (must be > 0).
     */
    function mintVoucher(address to, uint256 tenxAmount, uint256 seasonId) external onlyOwner {
        require(to != address(0), "Invalid recipient");
        require(tenxAmount > 0, "Invalid amount");
        require(seasonId > 0, "Invalid season");

        _tokenIdTracker.increment();
        uint256 tokenId = _tokenIdTracker.current();

        _tenxAmount[tokenId] = tenxAmount;
        _seasonId[tokenId] = seasonId;

        _safeMint(to, tokenId);

        emit VoucherMinted(to, tokenId, tenxAmount, seasonId);
    }

    /**
     * @notice Redeem a voucher. Burns the voucher and marks it as redeemed.
     * @param tokenId ID of the voucher to redeem.
     */
    function redeemVoucher(uint256 tokenId) external nonReentrant {
        require(_exists(tokenId), "Nonexistent token");
        require(ownerOf(tokenId) == msg.sender, "Not voucher owner");
        require(!_redeemed[tokenId], "Already redeemed");

        _redeemed[tokenId] = true;
        uint256 tenxAmount = _tenxAmount[tokenId];
        uint256 seasonId = _seasonId[tokenId];

        _burn(tokenId);

        emit VoucherRedeemed(msg.sender, tokenId, tenxAmount, seasonId);
    }

    /**
     * @notice Revoke (burn) a voucher. Only callable by the contract owner.
     * @param tokenId ID of the voucher to revoke.
     */
    function revokeVoucher(uint256 tokenId) external onlyOwner {
        require(_exists(tokenId), "Nonexistent token");
        require(!_redeemed[tokenId], "Already redeemed");

        address voucherOwner = ownerOf(tokenId);
        _burn(tokenId);

        emit VoucherRevoked(voucherOwner, tokenId);
    }

    /**
     * @notice Get voucher metadata.
     * @param tokenId ID of the voucher.
     */
    function getVoucherInfo(uint256 tokenId) external view returns (uint256 tenxAmount, uint256 seasonId, bool redeemed) {
        require(_exists(tokenId), "Nonexistent token");
        return (_tenxAmount[tokenId], _seasonId[tokenId], _redeemed[tokenId]);
    }

    /**
     * @notice List all voucher token IDs owned by a user.
     * @param user Address to query.
     */
    function vouchersOf(address user) external view returns (uint256[] memory tokenIds) {
        uint256 balance = balanceOf(user);
        tokenIds = new uint256[](balance);
        for (uint256 i = 0; i < balance; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(user, i);
        }
    }

    /**
     * @dev Override to enforce soulbound behavior and keep enumerability updated.
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721Enumerable) {
        if (from != address(0) && to != address(0)) {
            revert("Voucher is soulbound");
        }
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    /**
     * @dev Override approval-related functions to enforce soulbound behavior.
     */
    function approve(address, uint256) public pure override {
        revert("Voucher is soulbound");
    }

    function setApprovalForAll(address, bool) public pure override {
        revert("Voucher is soulbound");
    }

    function transferFrom(address, address, uint256) public pure override {
        revert("Voucher is soulbound");
    }

    function safeTransferFrom(address, address, uint256) public pure override {
        revert("Voucher is soulbound");
    }

    function safeTransferFrom(address, address, uint256, bytes memory) public pure override {
        revert("Voucher is soulbound");
    }

    /**
     * @dev Returns the base URI for computing {tokenURI}.
     */
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    /**
     * @notice Returns the metadata URI for a given token.
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "Nonexistent token");
        string memory base = _baseURI();
        uint256 seasonId = _seasonId[tokenId];
        if (bytes(base).length == 0) {
            return "";
        }
        return string(abi.encodePacked(base, "/", seasonId.toString(), "/", tokenId.toString(), ".json"));
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view override(ERC721Enumerable, ERC721) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Clear voucher data on burn.
     */
    function _burn(uint256 tokenId) internal override(ERC721) {
        super._burn(tokenId);
        delete _tenxAmount[tokenId];
        delete _seasonId[tokenId];
        // Keep redemption flag for historical queries
    }
}
