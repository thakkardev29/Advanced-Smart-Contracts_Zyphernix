// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract NFTMarketplace is ReentrancyGuard {

    address public marketplaceOwner;
    uint256 public platformFeeBP; // basis points (100 = 1%)
    address public platformFeeReceiver;

    struct MarketItem {
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 salePrice;
        address royaltyReceiver;
        uint256 royaltyBP;
        bool active;
    }

    mapping(address => mapping(uint256 => MarketItem)) private marketListings;

    /* ========== EVENTS ========== */

    event NFTListed(
        address indexed seller,
        address indexed nftContract,
        uint256 indexed tokenId,
        uint256 price,
        address royaltyReceiver,
        uint256 royaltyBP
    );

    event NFTPurchased(
        address indexed buyer,
        address indexed nftContract,
        uint256 indexed tokenId,
        uint256 price,
        address seller,
        address royaltyReceiver,
        uint256 royaltyPaid,
        uint256 platformFeePaid
    );

    event NFTUnlisted(
        address indexed seller,
        address indexed nftContract,
        uint256 indexed tokenId
    );

    event PlatformFeeUpdated(uint256 newFeeBP, address newReceiver);

    /* ========== CONSTRUCTOR ========== */

    constructor(uint256 _platformFeeBP, address _feeReceiver) {
        require(_platformFeeBP <= 1000, "Fee exceeds 10%");
        require(_feeReceiver != address(0), "Invalid fee receiver");

        marketplaceOwner = msg.sender;
        platformFeeBP = _platformFeeBP;
        platformFeeReceiver = _feeReceiver;
    }

    /* ========== MODIFIERS ========== */

    modifier onlyMarketplaceOwner() {
        require(msg.sender == marketplaceOwner, "Not authorized");
        _;
    }

    /* ========== ADMIN FUNCTIONS ========== */

    function updatePlatformFee(uint256 newFeeBP)
        external
        onlyMarketplaceOwner
    {
        require(newFeeBP <= 1000, "Fee exceeds limit");
        platformFeeBP = newFeeBP;

        emit PlatformFeeUpdated(newFeeBP, platformFeeReceiver);
    }

    function updateFeeReceiver(address newReceiver)
        external
        onlyMarketplaceOwner
    {
        require(newReceiver != address(0), "Invalid address");
        platformFeeReceiver = newReceiver;

        emit PlatformFeeUpdated(platformFeeBP, newReceiver);
    }

    /* ========== LISTING LOGIC ========== */

    function listNFT(
        address nftContract,
        uint256 tokenId,
        uint256 price,
        address royaltyReceiver,
        uint256 royaltyBP
    ) external {
        require(price > 0, "Price must be positive");
        require(royaltyBP <= 1000, "Royalty too high");
        require(!marketListings[nftContract][tokenId].active, "Already listed");

        IERC721 nft = IERC721(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "Not token owner");
        require(
            nft.getApproved(tokenId) == address(this) ||
            nft.isApprovedForAll(msg.sender, address(this)),
            "Marketplace not approved"
        );

        marketListings[nftContract][tokenId] = MarketItem({
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            salePrice: price,
            royaltyReceiver: royaltyReceiver,
            royaltyBP: royaltyBP,
            active: true
        });

        emit NFTListed(
            msg.sender,
            nftContract,
            tokenId,
            price,
            royaltyReceiver,
            royaltyBP
        );
    }

    /* ========== PURCHASE LOGIC ========== */

    function purchaseNFT(address nftContract, uint256 tokenId)
        external
        payable
        nonReentrant
    {
        MarketItem memory item = marketListings[nftContract][tokenId];
        require(item.active, "Listing inactive");
        require(msg.value == item.salePrice, "Incorrect ETH amount");
        require(
            item.royaltyBP + platformFeeBP <= 10000,
            "Fee overflow"
        );

        uint256 platformFee =
            (msg.value * platformFeeBP) / 10000;

        uint256 royaltyFee =
            (msg.value * item.royaltyBP) / 10000;

        uint256 sellerProceeds =
            msg.value - platformFee - royaltyFee;

        if (platformFee > 0) {
            payable(platformFeeReceiver).transfer(platformFee);
        }

        if (royaltyFee > 0 && item.royaltyReceiver != address(0)) {
            payable(item.royaltyReceiver).transfer(royaltyFee);
        }

        payable(item.seller).transfer(sellerProceeds);

        IERC721(item.nftContract).safeTransferFrom(
            item.seller,
            msg.sender,
            item.tokenId
        );

        delete marketListings[nftContract][tokenId];

        emit NFTPurchased(
            msg.sender,
            nftContract,
            tokenId,
            msg.value,
            item.seller,
            item.royaltyReceiver,
            royaltyFee,
            platformFee
        );
    }

    /* ========== LISTING MANAGEMENT ========== */

    function cancelListing(address nftContract, uint256 tokenId) external {
        MarketItem memory item = marketListings[nftContract][tokenId];
        require(item.active, "Not listed");
        require(item.seller == msg.sender, "Not seller");

        delete marketListings[nftContract][tokenId];
        emit NFTUnlisted(msg.sender, nftContract, tokenId);
    }

    function getListing(address nftContract, uint256 tokenId)
        external
        view
        returns (MarketItem memory)
    {
        return marketListings[nftContract][tokenId];
    }

    /* ========== FALLBACKS ========== */

    receive() external payable {
        revert("ETH not accepted");
    }

    fallback() external payable {
        revert("Invalid call");
    }
}
