// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/*
 * Basic ERC721 interface declaration
 */
interface IERC721 {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    function balanceOf(address account) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);

    function approve(address spender, uint256 tokenId) external;
    function getApproved(uint256 tokenId) external view returns (address);

    function setApprovalForAll(address operator, bool status) external;
    function isApprovedForAll(address owner, address operator) external view returns (bool);

    function transferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external;
}

/*
 * Receiver interface for safe transfers
 */
interface IERC721Receiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}

/*
 * Minimal ERC721 NFT implementation
 */
contract SimpleNFT is IERC721 {

    string public name;
    string public symbol;

    uint256 private _nextTokenId = 1;

    mapping(uint256 => address) private _tokenOwner;
    mapping(address => uint256) private _ownerBalance;
    mapping(uint256 => address) private _singleTokenApproval;
    mapping(address => mapping(address => bool)) private _operatorApproval;
    mapping(uint256 => string) private _metadataURI;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function balanceOf(address owner) public view override returns (uint256) {
        require(owner != address(0), "Invalid address");
        return _ownerBalance[owner];
    }

    function ownerOf(uint256 tokenId) public view override returns (address) {
        address holder = _tokenOwner[tokenId];
        require(holder != address(0), "Token not found");
        return holder;
    }

    function approve(address to, uint256 tokenId) public override {
        address tokenOwner = ownerOf(tokenId);
        require(to != tokenOwner, "Owner approval not needed");
        require(
            msg.sender == tokenOwner || isApprovedForAll(tokenOwner, msg.sender),
            "Approval denied"
        );

        _singleTokenApproval[tokenId] = to;
        emit Approval(tokenOwner, to, tokenId);
    }

    function getApproved(uint256 tokenId) public view override returns (address) {
        require(_tokenOwner[tokenId] != address(0), "Nonexistent token");
        return _singleTokenApproval[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) public override {
        require(operator != msg.sender, "Cannot self-approve");
        _operatorApproval[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address owner, address operator)
        public
        view
        override
        returns (bool)
    {
        return _operatorApproval[owner][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public override {
        require(_isAuthorized(msg.sender, tokenId), "Transfer not allowed");
        _executeTransfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId)
        public
        override
    {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public override {
        require(_isAuthorized(msg.sender, tokenId), "Transfer not allowed");
        _safeExecuteTransfer(from, to, tokenId, data);
    }

    function mint(address recipient, string memory uri) public {
        uint256 currentTokenId = _nextTokenId;
        _nextTokenId++;

        _tokenOwner[currentTokenId] = recipient;
        _ownerBalance[recipient] += 1;
        _metadataURI[currentTokenId] = uri;

        emit Transfer(address(0), recipient, currentTokenId);
    }

    function tokenURI(uint256 tokenId) public view returns (string memory) {
        require(_tokenOwner[tokenId] != address(0), "URI query failed");
        return _metadataURI[tokenId];
    }

    function _executeTransfer(address from, address to, uint256 tokenId) internal {
        require(ownerOf(tokenId) == from, "Incorrect owner");
        require(to != address(0), "Invalid recipient");

        _ownerBalance[from] -= 1;
        _ownerBalance[to] += 1;
        _tokenOwner[tokenId] = to;

        delete _singleTokenApproval[tokenId];
        emit Transfer(from, to, tokenId);
    }

    function _safeExecuteTransfer(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) internal {
        _executeTransfer(from, to, tokenId);
        require(
            _verifyERC721Receiver(from, to, tokenId, data),
            "Receiver rejected tokens"
        );
    }

    function _isAuthorized(address spender, uint256 tokenId)
        internal
        view
        returns (bool)
    {
        address tokenOwner = ownerOf(tokenId);
        return (
            spender == tokenOwner ||
            getApproved(tokenId) == spender ||
            isApprovedForAll(tokenOwner, spender)
        );
    }

    function _verifyERC721Receiver(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) private returns (bool) {
        if (to.code.length > 0) {
            try
                IERC721Receiver(to).onERC721Received(
                    msg.sender,
                    from,
                    tokenId,
                    data
                )
            returns (bytes4 response) {
                return response == IERC721Receiver.onERC721Received.selector;
            } catch {
                return false;
            }
        }
        return true;
    }
}
