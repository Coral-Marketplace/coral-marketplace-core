// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
* Interface for royalties following EIP-2981 (https://eips.ethereum.org/EIPS/eip-2981).
*/
interface IERC2981 is IERC165 {
    function royaltyInfo(
        uint256 _tokenId,
        uint256 _salePrice
    ) external view returns (
        address receiver,
        uint256 royaltyAmount
    );
}

contract CoralMarketplace is Ownable, ReentrancyGuard {
	// bytes4(keccak256("royaltyInfo(uint256,uint256)")) == 0x2a55205a
	bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;

	address loanAddress;
	using Counters for Counters.Counter;
	Counters.Counter private _itemIds;
	Counters.Counter private _onRegularSale;
	Counters.Counter private _onAuction;
	Counters.Counter private _onRaffle;
	uint256 private _marketFee;

	enum TypeItem {
		Regular, 
		Auction,
		Raffle
	}

	struct MarketItem {
		uint256 itemId; // Incremental ID in the market contract
		address nftContract;
		uint256 tokenId; // Incremental ID in the NFT contract
		address payable seller;
		address payable owner;
		address creator;
		uint256 price;
		uint256 marketFee; // Market fee at the moment of creating the item
		bool onSale;
		TypeItem typeItem;
		MarketItemSale[] sales;
	}

	struct MarketItemSale {
		address seller;
		address buyer;
		uint256 price;
		TypeItem typeItem;
	}

	struct AuctionData {
		uint256 deadline;
		uint256 minBid;
		address highestBidder;
		uint256 highestBid;
	}

	struct RaffleData {
		uint256 deadline;
		uint256 totalValue;
		mapping(address => uint256) addressToAmount;
		mapping(uint => address) indexToAddress;
		uint256 totalAddresses;
	}

	mapping(uint256 => MarketItem) private idToMarketItem;

	mapping(uint256 => AuctionData) private idToAuctionData;

	mapping(uint256 => RaffleData) private idToRaffleData;

	event MarketItemUpdate(uint256 indexed itemId, address indexed nftContract, uint256 indexed tokenId,
		address seller, address creator, uint256 price, uint256 marketFee, TypeItem typeItem);

	event MarketItemSold(uint256 indexed itemId, address indexed nftContract, uint256 indexed tokenId,
		address seller, address buyer, uint256 price, TypeItem typeItem);

	event MarketFeeChanged(uint256 prevValue, uint256 newValue);

	event RoyaltiesPaid(uint256 indexed tokenId, uint value);
	
	constructor(uint256 newMarketFee) {
		_marketFee = newMarketFee;
	}

	/**
	 * Returns current market fee percentage with two decimal points.
	 * E.g. 250 --> 2.5%
	 */
	function getMarketFee() public view returns (uint256) {
		return _marketFee;
	}

	/**
	 * Sets market fee percentage with two decimal points.
	 * E.g. 250 --> 2.5%
	 */
	function setMarketFee(uint256 newMarketFee) public virtual onlyOwner {
		require(newMarketFee <= 5000, 'CoralMarketplace: Market fee value cannot be higher than 5000.');
        uint256 prevMarketFee = _marketFee;
        _marketFee = newMarketFee;
        emit MarketFeeChanged(prevMarketFee, newMarketFee);
    }

	/**
	 * Sets loan contract address.
	 */
	function setLoanAddress(address _loanAddress) public virtual onlyOwner {
		loanAddress = _loanAddress;
    }

	/**
	 * Creates new market item.
	 */
	function createMarketItem(address nftContract, uint256 tokenId) public returns (uint256) {
		require (msg.sender == IERC721(nftContract).ownerOf(tokenId), "CoralMarketplace: Only owner of token can create market item.");

		// Map new MarketItem
		_itemIds.increment();
		uint256 itemId = _itemIds.current();
		idToMarketItem[itemId].itemId = itemId;
		idToMarketItem[itemId].nftContract = nftContract;
		idToMarketItem[itemId].tokenId = tokenId;
		idToMarketItem[itemId].creator = msg.sender;
		idToMarketItem[itemId].owner = payable(msg.sender);

		emit MarketItemUpdate(itemId, nftContract, tokenId, msg.sender, msg.sender, 0, 0, TypeItem.Regular);

		return itemId;
	}

	/**
	 * Updates a market item owner from CoralLoan contract.
	 */
	function updateMarketItemOwner(uint256 itemId, address newItemOwner) public virtual {
		require (msg.sender == loanAddress, "CoralMarketplace: Only loan contract can change item owner.");

		idToMarketItem[itemId].owner = payable(newItemOwner);
	}

	/**
	 * Returns detail of a market item.
	 */
	function fetchItem(uint256 itemId) public view returns (MarketItem memory) {
		return idToMarketItem[itemId];
	}

	/**
	 * Returns items created by caller.
	 */
	function fetchMyItemsCreated() public view returns (MarketItem[] memory) {
		return fetchAddressItemsCreated(msg.sender);
	}

	/**
	 * Returns items created by an address.
	 */
	function fetchAddressItemsCreated(address targetAddress) public view returns (MarketItem[] memory) {
		// Get total number of items created by target address
		uint totalItemCount = _itemIds.current();
		uint itemCount = 0;
		uint currentIndex = 0;
		for (uint i = 0; i < totalItemCount; i++) {
			if (idToMarketItem[i + 1].creator == targetAddress) {
				itemCount += 1;
			}
		}

		// Initialize array
		MarketItem[] memory items = new MarketItem[](itemCount);

		// Fill array
		for (uint i = 0; i < totalItemCount; i++) {
			if (idToMarketItem[i + 1].creator == targetAddress) {
				uint currentId = idToMarketItem[i + 1].itemId;
				MarketItem storage currentItem = idToMarketItem[currentId];
				items[currentIndex] = currentItem;
				currentIndex += 1;
			}
		}

		return items;
	}

	/**
	 * Returns items currently on sale (regular, auction or raffle) by caller.
	 */
	function fetchMyItemsOnSale() public view returns (MarketItem[] memory) {
		return fetchAddressItemsOnSale(msg.sender);
	}

	/**
	 * Returns items currently on sale (regular, auction or raffle) by an address.
	 */
	function fetchAddressItemsOnSale(address targetAddress) public view returns (MarketItem[] memory) {
		// Get total number of items on sale by target address
		uint totalItemCount = _itemIds.current();
		uint itemCount = 0;
		uint currentIndex = 0;
		for (uint i = 0; i < totalItemCount; i++) {
			if (idToMarketItem[i + 1].seller == targetAddress && idToMarketItem[i + 1].onSale
				&& (idToMarketItem[i + 1].typeItem == TypeItem.Regular || idToMarketItem[i + 1].typeItem == TypeItem.Auction)) {
				itemCount += 1;
			}
		}

		// Initialize array
		MarketItem[] memory items = new MarketItem[](itemCount);

		// Fill array
		for (uint i = 0; i < totalItemCount; i++) {
			if (idToMarketItem[i + 1].seller == targetAddress && idToMarketItem[i + 1].onSale
				&& (idToMarketItem[i + 1].typeItem == TypeItem.Regular || idToMarketItem[i + 1].typeItem == TypeItem.Auction)) {
				uint currentId = idToMarketItem[i + 1].itemId;
				MarketItem storage currentItem = idToMarketItem[currentId];
				items[currentIndex] = currentItem;
				currentIndex += 1;
			}
		}

		return items;
	}

	/**
	 * Returns items owned by caller.
	 */
	function fetchMyItemsOwned() public view returns (MarketItem[] memory) {
		return fetchAddressItemsOwned(msg.sender);
	}

	/**
	 * Returns items owned by an address.
	 */
	function fetchAddressItemsOwned(address targetAddress) public view returns (MarketItem[] memory) {
		// Get total number of items owned by target address
		uint totalItemCount = _itemIds.current();
		uint itemCount = 0;
		uint currentIndex = 0;
		for (uint i = 0; i < totalItemCount; i++) {
			if (idToMarketItem[i + 1].owner == targetAddress) {
				itemCount += 1;
			}
		}

		// Initialize array
		MarketItem[] memory items = new MarketItem[](itemCount);

		// Fill array
		for (uint i = 0; i < totalItemCount; i++) {
			if (idToMarketItem[i + 1].owner == targetAddress) {
				uint currentId = idToMarketItem[i + 1].itemId;
				MarketItem storage currentItem = idToMarketItem[currentId];
				items[currentIndex] = currentItem;
				currentIndex += 1;
			}
		}

		return items;
	}

	/////////////////////////// REGULAR SALE ////////////////////////////////////

	/**
	 * Puts on sale a new NFT.
	 */
	function putNewNftOnSale(address nftContract, uint256 tokenId, uint256 price) public {
		require(price > 0, "CoralMarketplace: Price must be greater than 0.");

		// Create market item
		uint256 itemId = createMarketItem(nftContract, tokenId);

		// Put on sale
		putMarketItemOnSale(itemId, price);
	}

	/**
	 * Puts on sale existing market item.
	 */
	function putMarketItemOnSale(uint256 itemId, uint256 price) public {
		require(idToMarketItem[itemId].itemId > 0, "CoralMarketplace: itemId does not exist.");
		require(!idToMarketItem[itemId].onSale, "CoralMarketplace: This item is already on sale.");
		require(price > 0, "CoralMarketplace: Price must be greater than 0.");

		// Transfer ownership of the token to this contract
		IERC721(idToMarketItem[itemId].nftContract).transferFrom(msg.sender, address(this), idToMarketItem[itemId].tokenId);

		// Update MarketItem
		idToMarketItem[itemId].seller = payable(msg.sender);
		idToMarketItem[itemId].owner = payable(address(0));
		idToMarketItem[itemId].price = price;
		idToMarketItem[itemId].marketFee = _marketFee;
		idToMarketItem[itemId].onSale = true;
		idToMarketItem[itemId].typeItem = TypeItem.Regular;

		_onRegularSale.increment();

		emit MarketItemUpdate(itemId, idToMarketItem[itemId].nftContract, idToMarketItem[itemId].tokenId, msg.sender, 
			idToMarketItem[itemId].creator, price, _marketFee, TypeItem.Regular);
	}

	/**
	 * Creates a new sale for a existing market item.
	 */
	function createMarketSale(uint256 itemId) public payable nonReentrant {
		require(idToMarketItem[itemId].onSale && idToMarketItem[itemId].typeItem == TypeItem.Regular, 
			"CoralMarketplace: This item is not currently on sale.");
		uint256 price = idToMarketItem[itemId].price;
		require(msg.value == price, "CoralMarketplace: Value of transaction must be equal to sale price.");

		// Process transaction
		_createItemTransaction(itemId, msg.sender, msg.value);

		// Update item in the mapping
		address payable seller = idToMarketItem[itemId].seller;
		idToMarketItem[itemId].owner = payable(msg.sender);
		idToMarketItem[itemId].onSale = false;
		idToMarketItem[itemId].seller = payable(address(0));
		idToMarketItem[itemId].price = 0;
		idToMarketItem[itemId].sales.push(MarketItemSale(seller, msg.sender, price, TypeItem.Regular));

		_onRegularSale.decrement();

		emit MarketItemSold(itemId, idToMarketItem[itemId].nftContract, idToMarketItem[itemId].tokenId, seller, 
			msg.sender, price, TypeItem.Regular);
	}

	/**
	 * Unlist item from regular sale.
	 */
	function unlistMarketItem(uint256 itemId) public {
		require(idToMarketItem[itemId].onSale && idToMarketItem[itemId].typeItem == TypeItem.Regular, 
			"CoralMarketplace: This item is not currently on sale.");
		require(msg.sender == idToMarketItem[itemId].seller, "CoralMarketplace: Only seller can unlist item.");

		// Transfer ownership back to seller
		IERC721(idToMarketItem[itemId].nftContract).transferFrom(address(this), msg.sender, idToMarketItem[itemId].tokenId);

		// Update MarketItem
		idToMarketItem[itemId].owner = payable(msg.sender);
		idToMarketItem[itemId].onSale = false;
		idToMarketItem[itemId].seller = payable(address(0));
		idToMarketItem[itemId].price = 0;

		_onRegularSale.decrement();
	}

	/**
	 * Returns market items on regular sale or auction.
	 */
	function fetchItemsOnSale() public view returns (MarketItem[] memory) {
		uint currentIndex = 0;

		// Initialize array
		MarketItem[] memory items = new MarketItem[](_onRegularSale.current());

		// Fill array
		for (uint i = 0; i < _itemIds.current(); i++) {
			if (idToMarketItem[i + 1].onSale && (idToMarketItem[i + 1].typeItem == TypeItem.Regular
				|| idToMarketItem[i + 1].typeItem == TypeItem.Auction)) {
				uint currentId = idToMarketItem[i + 1].itemId;
				MarketItem storage currentItem = idToMarketItem[currentId];
				items[currentIndex] = currentItem;
				currentIndex += 1;
			}
		}

		return items;
	}

	/////////////////////////// AUCTION ////////////////////////////////////

	/**
	 * Creates an auction for a new item.
	 */
	function createNewNftAuction(address nftContract, uint256 tokenId, uint256 numMinutes, uint256 minBid) public {
		require(numMinutes <= 44640, "CoralMarketplace: Number of minutes cannot be greater than 44,640."); // 44,640 min = 1 month

		// Create market item
		uint256 itemId = createMarketItem(nftContract, tokenId);

		// Create auction
		createMarketItemAuction(itemId, numMinutes, minBid);
	}

	/**
	 * Creates an auction from an existing market item.
	 */
	function createMarketItemAuction(uint256 itemId, uint256 numMinutes, uint256 minBid) public {
		require(idToMarketItem[itemId].itemId > 0, "CoralMarketplace: itemId does not exist.");
		require(!idToMarketItem[itemId].onSale, "CoralMarketplace: This item is already on sale.");
		require(numMinutes <= 44640, "CoralMarketplace: Number of minutes cannot be greater than 44,640."); // 44,640 min = 1 month

		// Transfer ownership of the token to this contract
		IERC721(idToMarketItem[itemId].nftContract).transferFrom(msg.sender, address(this), idToMarketItem[itemId].tokenId);

		// Update MarketItem
		idToMarketItem[itemId].seller = payable(msg.sender);
		idToMarketItem[itemId].owner = payable(address(0));
		idToMarketItem[itemId].price = 0;
		idToMarketItem[itemId].marketFee = _marketFee;
		idToMarketItem[itemId].onSale = true;
		idToMarketItem[itemId].typeItem = TypeItem.Auction;

		// Create AuctionData
		uint256 deadline = (block.timestamp + numMinutes * 1 minutes);
		idToAuctionData[itemId].deadline = deadline;
		idToAuctionData[itemId].minBid = minBid;
		idToAuctionData[itemId].highestBidder = address(0);
		idToAuctionData[itemId].highestBid = 0;

		_onAuction.increment();

		emit MarketItemUpdate(itemId, idToMarketItem[itemId].nftContract, idToMarketItem[itemId].tokenId, msg.sender, 
			msg.sender, 0, _marketFee, TypeItem.Auction);
	}

	/**
	 * Adds bid to an active auction.
	 */
	function createBid(uint256 itemId) public payable {
		require(idToMarketItem[itemId].onSale && idToMarketItem[itemId].typeItem == TypeItem.Auction &&
			idToAuctionData[itemId].deadline >= block.timestamp, "CoralMarketplace: There is no active auction for this item.");
		require(msg.value >= idToAuctionData[itemId].minBid || msg.sender == idToAuctionData[itemId].highestBidder,
			"CoralMarketplace: Bid value cannot be lower than minimum bid.");
		require(msg.value > idToAuctionData[itemId].highestBid || msg.sender == idToAuctionData[itemId].highestBidder,
			"CoralMarketplace: Bid value cannot be lower than highest bid.");
		
		// Update AuctionData
		if (msg.sender == idToAuctionData[itemId].highestBidder) {
			// Highest bidder increases bid value
			idToAuctionData[itemId].highestBid += msg.value;
		} else {
			if (idToAuctionData[itemId].highestBidder != address(0)) {
				// Return bid amount to previous highest bidder, if exists
				payable(idToAuctionData[itemId].highestBidder).transfer(idToAuctionData[itemId].highestBid);
			}
			idToAuctionData[itemId].highestBid = msg.value;
			idToAuctionData[itemId].highestBidder = msg.sender;
		}

		// Extend deadline if we are on last 10 minutes
		uint256 secsToDeadline = idToAuctionData[itemId].deadline - block.timestamp;
		if (secsToDeadline < 600) {
			idToAuctionData[itemId].deadline += (600 - secsToDeadline);
		}
	}

	/**
	 * Distributes NFT and bidded amount after auction deadline is reached.
	 */
	function endAuction(uint256 itemId) public nonReentrant {
		require(idToMarketItem[itemId].onSale && idToMarketItem[itemId].typeItem == TypeItem.Auction, 
			"CoralMarketplace: There is no auction for this item.");
		require(idToAuctionData[itemId].deadline < block.timestamp, 
			"CoralMarketplace: Auction deadline has not been reached yet.");

		// Update MarketItem
		idToMarketItem[itemId].onSale = false;
		_onAuction.decrement();

		if (idToAuctionData[itemId].highestBid > 0) {
			// Create transaction
			_createItemTransaction(itemId, idToAuctionData[itemId].highestBidder, idToAuctionData[itemId].highestBid);

			// Update item in the mapping
			idToMarketItem[itemId].owner = payable(idToAuctionData[itemId].highestBidder);
			idToMarketItem[itemId].sales.push(MarketItemSale(idToMarketItem[itemId].seller, idToAuctionData[itemId].highestBidder,
				idToAuctionData[itemId].highestBid, TypeItem.Auction));

			emit MarketItemSold(itemId, idToMarketItem[itemId].nftContract, idToMarketItem[itemId].tokenId, 
				idToMarketItem[itemId].seller, idToAuctionData[itemId].highestBidder, idToAuctionData[itemId].highestBid, TypeItem.Auction);
		} else {
			// Transfer ownership of the token back to seller
			IERC721(idToMarketItem[itemId].nftContract).transferFrom(address(this), idToMarketItem[itemId].seller,
				idToMarketItem[itemId].tokenId);
			// Update item in the mapping
			idToMarketItem[itemId].owner = payable(idToMarketItem[itemId].seller);
		}

		delete idToAuctionData[itemId];
	} 

	/**
	 * Returns auction data.
	 */
	function fetchAuctionData(uint256 itemId) public view returns (AuctionData memory auctionData) {
		require(idToMarketItem[itemId].onSale && idToMarketItem[itemId].typeItem == TypeItem.Auction, 
			"CoralMarketplace: There is no auction open for this item.");
		return idToAuctionData[itemId];
	}

	/**
	 * Returns active auctions.
	 */
	function fetchAuctions() public view returns (MarketItem[] memory) {
		uint currentIndex = 0;

		// Initialize array
		MarketItem[] memory items = new MarketItem[](_onAuction.current());

		// Fill array
		for (uint i = 0; i < _itemIds.current(); i++) {
			if (idToMarketItem[i + 1].onSale && idToMarketItem[i + 1].typeItem == TypeItem.Auction) {
				uint currentId = idToMarketItem[i + 1].itemId;
				MarketItem storage currentItem = idToMarketItem[currentId];
				items[currentIndex] = currentItem;
				currentIndex += 1;
			}
		}

		return items;
	}

	/////////////////////////// RAFFLE ////////////////////////////////////

	/**
	 * Creates a raffle for a new item.
	 */
	function createNewNftRaffle(address nftContract, uint256 tokenId, uint256 numMinutes) public {
		require(numMinutes <= 525600, "CoralMarketplace: Number of minutes cannot be greater than 525,600."); // 525,600 min = 1 year

		// Create market item
		uint256 itemId = createMarketItem(nftContract, tokenId);

		// Create raffle
		createMarketItemRaffle(itemId, numMinutes);
	}

	/**
	 * Creates a raffle from an existing market item.
	 */
	function createMarketItemRaffle(uint256 itemId, uint256 numMinutes) public {
		require(idToMarketItem[itemId].itemId > 0, "CoralMarketplace: itemId does not exist.");
		require(!idToMarketItem[itemId].onSale, "CoralMarketplace: This item is already on sale.");
		require(numMinutes <= 525600, "CoralMarketplace: Number of minutes cannot be greater than 525,600."); // 525,600 min = 1 year

		// Transfer ownership of the token to this contract
		IERC721(idToMarketItem[itemId].nftContract).transferFrom(msg.sender, address(this), idToMarketItem[itemId].tokenId);

		// Update MarketItem
		idToMarketItem[itemId].seller = payable(msg.sender);
		idToMarketItem[itemId].owner = payable(address(0));
		idToMarketItem[itemId].price = 0;
		idToMarketItem[itemId].marketFee = _marketFee;
		idToMarketItem[itemId].onSale = true;
		idToMarketItem[itemId].typeItem = TypeItem.Raffle;

		// Create RaffleData
		uint256 deadline = (block.timestamp + numMinutes * 1 minutes);
		idToRaffleData[itemId].deadline = deadline;

		_onRaffle.increment();

		emit MarketItemUpdate(itemId, idToMarketItem[itemId].nftContract, idToMarketItem[itemId].tokenId, msg.sender, 
			msg.sender, 0, _marketFee, TypeItem.Raffle);
	}

	/**
	 * Adds entry to an active raffle.
	 */
	function enterRaffle(uint256 itemId) public payable {
		require(idToMarketItem[itemId].onSale && idToMarketItem[itemId].typeItem == TypeItem.Raffle, 
			"CoralMarketplace: There is no raffle active for this item.");
		require(msg.value >= 1 * (10**18), "CoralMarketplace: Value of transaction must be at least 1 REEF.");

		uint256 value = msg.value / (10**18);
		
		// Update RaffleData
		if (!(idToRaffleData[itemId].addressToAmount[msg.sender] > 0)) {
			idToRaffleData[itemId].indexToAddress[idToRaffleData[itemId].totalAddresses] = payable(msg.sender);
			idToRaffleData[itemId].totalAddresses += 1;
		}
		idToRaffleData[itemId].addressToAmount[msg.sender] += value;
		idToRaffleData[itemId].totalValue += value;
	}

	/**
	 * Ends open raffle.
	 */
	function endRaffle(uint256 itemId) public nonReentrant {
		require(idToMarketItem[itemId].onSale && idToMarketItem[itemId].typeItem == TypeItem.Raffle, 
			"CoralMarketplace: There is no raffle open for this item.");
		require(idToRaffleData[itemId].deadline < block.timestamp, 
			"CoralMarketplace: Raffle deadline has not been reached yet.");

		// Update MarketItem
		idToMarketItem[itemId].onSale = false;
		_onRaffle.decrement();

		// Check if there are participants in the raffle
		if (idToRaffleData[itemId].totalAddresses == 0) {
			address payable seller = idToMarketItem[itemId].seller;
			// Transfer ownership back to seller
			IERC721(idToMarketItem[itemId].nftContract).transferFrom(address(this), seller, idToMarketItem[itemId].tokenId);

			// Update item in the mapping
			idToMarketItem[itemId].owner = seller;

			delete idToRaffleData[itemId];
		} else {
			// Choose winner for the raffle
			uint256 totalValue = idToRaffleData[itemId].totalValue;
			uint256 indexWinner = _pseudoRand() % totalValue;
			uint256 lastIndex = 0;
			for (uint i = 0; i < idToRaffleData[itemId].totalAddresses; i++) {
				address currAddress = idToRaffleData[itemId].indexToAddress[i];
				lastIndex += idToRaffleData[itemId].addressToAmount[currAddress];
				if (indexWinner < lastIndex) {
					address payable seller = idToMarketItem[itemId].seller;
					_createItemTransaction(itemId, currAddress, totalValue * (10**18));

					// Update item in the mapping
					idToMarketItem[itemId].owner = payable(currAddress);
					idToMarketItem[itemId].sales.push(MarketItemSale(seller, currAddress, totalValue * (10**18), TypeItem.Raffle));

					delete idToRaffleData[itemId];

					break;
				}
			}

			emit MarketItemSold(itemId, idToMarketItem[itemId].nftContract, idToMarketItem[itemId].tokenId, 
				idToMarketItem[itemId].seller, msg.sender, totalValue, TypeItem.Raffle);
		}
	} 

	/**
	 * Returns deadline of raffle and amount contributed by caller.
	 */
	function fetchRaffleData(uint256 itemId) public view returns (uint256 deadline, uint256 contribution) {
		require(idToMarketItem[itemId].onSale && idToMarketItem[itemId].typeItem == TypeItem.Raffle, 
			"CoralMarketplace: There is no raffle open for this item.");
		return (idToRaffleData[itemId].deadline, idToRaffleData[itemId].addressToAmount[msg.sender] * (10**18));
	}

	/**
	 * Returns active raffles.
	 */
	function fetchRaffles() public view returns (MarketItem[] memory) {
		uint currentIndex = 0;

		// Initialize array
		MarketItem[] memory items = new MarketItem[](_onRaffle.current());

		// Fill array
		for (uint i = 0; i < _itemIds.current(); i++) {
			if (idToMarketItem[i + 1].onSale && idToMarketItem[i + 1].typeItem == TypeItem.Raffle) {
				uint currentId = idToMarketItem[i + 1].itemId;
				MarketItem storage currentItem = idToMarketItem[currentId];
				items[currentIndex] = currentItem;
				currentIndex += 1;
			}
		}

		return items;
	}

	/////////////////////////// UTILS ////////////////////////////////////

	/**
	 * Pays royalties to the address designated by the NFT contract and returns the sale place
	 * minus the royalties payed.
	 */
	function _deduceRoyalties(address nftContract, uint256 tokenId, uint256 grossSaleValue, address payable seller) 
		internal returns (uint256 netSaleAmount) {
        // Get amount of royalties to pay and recipient
        (address royaltiesReceiver, uint256 royaltiesAmount) = IERC2981(nftContract).royaltyInfo(tokenId, grossSaleValue);

    	// If seller and royalties receiver are the same, royalties will not be deduced
        if (seller == royaltiesReceiver) {
			return grossSaleValue;
        }

        // Deduce royalties from sale value
        uint256 netSaleValue = grossSaleValue - royaltiesAmount;

        // Transfer royalties to rightholder if amount is not 0
        if (royaltiesAmount > 0) {
			(bool success, ) = royaltiesReceiver.call{value: royaltiesAmount}("");
			require(success, "CoralMarketplace: Royalties transfer failed.");
        }

        // Broadcast royalties payment
        emit RoyaltiesPaid(tokenId, royaltiesAmount);

        return netSaleValue;
    }

	/**
	 * Gets a pseudo-random number
	 */
	function _pseudoRand() internal view returns(uint256) {
		uint256 seed = uint256(keccak256(abi.encodePacked(
			block.timestamp + block.difficulty +
			((uint256(keccak256(abi.encodePacked(block.coinbase)))) / (block.timestamp)) +
			block.gaslimit + 
			((uint256(keccak256(abi.encodePacked(msg.sender)))) / (block.timestamp)) +
			block.number			
		)));

		return seed;
	}

	/**
	 * Creates transaction of token and selling amount
	 */
	function _createItemTransaction(uint256 itemId, address tokenRecipient, uint256 saleValue) internal {
		// Pay royalties
		address nftContract = idToMarketItem[itemId].nftContract;
		uint256 tokenId = idToMarketItem[itemId].tokenId;
		address payable seller = idToMarketItem[itemId].seller;
		if (_checkRoyalties(nftContract)) {
            saleValue = _deduceRoyalties(nftContract, tokenId, saleValue, seller);
        }

		// Pay market fee
		uint256 marketFee = (saleValue * idToMarketItem[itemId].marketFee) / 10000;
		(bool successFee, ) = owner().call{value: marketFee}("");
		require(successFee, "CoralMarketplace: Market fee transfer failed.");
		uint256 netSaleValue = saleValue - marketFee;

		// Transfer value of the transaction to the seller
		(bool successTx, ) = seller.call{value: netSaleValue}("");
		(successTx, "CoralMarketplace: Seller payment transfer failed.");

		// Transfer ownership of the token to buyer
		IERC721(nftContract).transferFrom(address(this), tokenRecipient, tokenId);
	}

	/**
	 * Checks if a contract supports EIP-2981 for royalties.
	 * View EIP-165 (https://eips.ethereum.org/EIPS/eip-165).
	 */
	function _checkRoyalties(address _contract) internal view returns (bool) {
        (bool success) = IERC165(_contract).supportsInterface(_INTERFACE_ID_ERC2981);
		return success;
    }

}