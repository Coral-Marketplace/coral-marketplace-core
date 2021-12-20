// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract CoralNFT is Ownable, ERC721URIStorage {
	// bytes4(keccak256("royaltyInfo(uint256,uint256)")) == 0x2a55205a
	bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;
	// bytes4(keccak256("hasMutableURI(uint256))")) == 0xc962d178
	bytes4 private constant _INTERFACE_ID_MUTABLE_URI = 0xc962d178;

	using Counters for Counters.Counter;
	Counters.Counter private _tokenIds;
	address marketplaceAddress;
	address loanAddress;

	mapping(bytes4 => bool) private _supportedInterfaces;

	struct RoyaltyInfo {
        address recipient;
        uint24 amount;
    }

	mapping(uint256 => RoyaltyInfo) internal _royalties;

	mapping(uint256 => bool) internal _mutableMetadataMapping;
	
	constructor(address _marketplaceAddress, address _loanAddress) ERC721("Coral NFT", "CORAL") {
		marketplaceAddress = _marketplaceAddress;
		loanAddress = _loanAddress;
	}

	/**
	 * Creates a new token
	 */
	function createToken(string memory _tokenURI, address _royaltyRecipient, uint256 _royaltyValue, bool _mutableMetada) public returns (uint) {
		_tokenIds.increment();
		uint256 tokenId = _tokenIds.current();

		_mint(msg.sender, tokenId);
		_setTokenURI(tokenId, _tokenURI);
		setApprovalForAll(marketplaceAddress, true);
		setApprovalForAll(loanAddress, true);

		if (_royaltyValue > 0) {
            _setTokenRoyalty(tokenId, _royaltyRecipient, _royaltyValue);
        }

		_mutableMetadataMapping[tokenId] = _mutableMetada;

		return tokenId;
	}

	/**
	 * Sets tokenURI for a certain token.
	 */
	function setTokenURI(uint256 _tokenId, string memory _tokenURI) public {
        require(msg.sender == ownerOf(_tokenId), 'CoralNFT: Only token owner can set tokenURI.');
		require(_mutableMetadataMapping[_tokenId], 'CoralNFT: The metadata of this token is immutable.');
        _setTokenURI(_tokenId, _tokenURI);
    }

	/**
	 * Returns whether or not a token has mutable URI.
	 */
    function hasMutableURI(uint256 _tokenId) external view returns (bool mutableMetadata) {
        return _mutableMetadataMapping[_tokenId];
    }

	/**
	 * Returns royalties recipient and amount for a certain token and sale value,
	 * following EIP-2981 guidelines (https://eips.ethereum.org/EIPS/eip-2981).
	 */
    function royaltyInfo(uint256 _tokenId, uint256 _saleValue) external view returns (address receiver, uint256 royaltyAmount) {
        RoyaltyInfo memory royalty = _royalties[_tokenId];
        return (royalty.recipient, (_saleValue * royalty.amount) / 10000);
    }

	/**
	 * Overrides supportsInterface method to include support for EIP-2981 and mutable URI interfaces.
	 */
    function supportsInterface(bytes4 _interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(_interfaceId) || _interfaceId == _INTERFACE_ID_ERC2981 
			|| _interfaceId == _INTERFACE_ID_MUTABLE_URI;
    }

	/**
	 * Sets token royalties recipient and percentage value (with two decimals) for a certain token.
	 */
	function _setTokenRoyalty(uint256 _tokenId, address _recipient, uint256 _value) internal {
        require(_value <= 5000, 'CoralNFT: Royalties value cannot be higher than 5000.');
        _royalties[_tokenId] = RoyaltyInfo(_recipient, uint24(_value));
    }

}