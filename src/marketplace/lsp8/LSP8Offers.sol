// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.22;

import {ILSP8IdentifiableDigitalAsset} from
    "@lukso/lsp-smart-contracts/contracts/LSP8IdentifiableDigitalAsset/ILSP8IdentifiableDigitalAsset.sol";
import {Module} from "../common/Module.sol";
import {ILSP8Listings, LSP8Listing} from "./ILSP8Listings.sol";
import {ILSP8Offers, LSP8Offer} from "./ILSP8Offers.sol";

contract LSP8Offers is ILSP8Offers, Module {
    error NotPlaced(uint256 listingId, address buyer);
    error InvalidOfferDuration(uint256 secondsUntilExpiration);
    error InactiveListing(uint256 listingId);
    error InactiveOffer(uint256 listingId, address buyer);
    error Unpaid(uint256 listingId, address buyer, uint256 amount);

    ILSP8Listings public listings;
    // listing id -> buyer -> offer
    mapping(uint256 => mapping(address => LSP8Offer)) private _offers;

    constructor() {
        _disableInitializers();
    }

    function initialize(address newOwner_, ILSP8Listings listings_) external initializer {
        Module._initialize(newOwner_);
        listings = listings_;
    }

    function isPlacedOffer(uint256 listingId, address buyer) public view override returns (bool) {
        return _offers[listingId][buyer].expirationTime != 0;
    }

    function isActiveOffer(uint256 listingId, address buyer) public view override returns (bool) {
        return _offers[listingId][buyer].expirationTime > block.timestamp;
    }

    function getOffer(uint256 listingId, address buyer) public view override returns (LSP8Offer memory) {
        if (!isPlacedOffer(listingId, buyer)) {
            revert NotPlaced(listingId, buyer);
        }
        return _offers[listingId][buyer];
    }

    function place(uint256 listingId, uint256 secondsUntilExpiration)
        external
        payable
        override
        whenNotPaused
        nonReentrant
    {
        LSP8Listing memory listing = listings.getListing(listingId);
        if (!listings.isActiveListing(listingId)) {
            revert InactiveListing(listingId);
        }
        if ((secondsUntilExpiration < 1 hours) || (secondsUntilExpiration > 28 days)) {
            revert InvalidOfferDuration(secondsUntilExpiration);
        }
        LSP8Offer memory lastOffer = _offers[listingId][msg.sender];
        uint256 price = msg.value + lastOffer.price;
        uint256 expirationTime = block.timestamp + secondsUntilExpiration;
        _offers[listingId][msg.sender] = LSP8Offer({price: price, expirationTime: expirationTime});
        emit Placed(listingId, msg.sender, listing.tokenId, price, expirationTime);
    }

    function cancel(uint256 listingId) external override whenNotPaused nonReentrant {
        LSP8Offer memory offer = getOffer(listingId, msg.sender);
        delete _offers[listingId][msg.sender];
        (bool success,) = msg.sender.call{value: offer.price}("");
        if (!success) {
            revert Unpaid(listingId, msg.sender, offer.price);
        }
        emit Canceled(listingId, msg.sender, offer.price);
    }

    function accept(uint256 listingId, address buyer) external override whenNotPaused nonReentrant onlyMarketplace {
        if (!listings.isActiveListing(listingId)) {
            revert InactiveListing(listingId);
        }
        LSP8Offer memory offer = getOffer(listingId, buyer);
        if (!isActiveOffer(listingId, buyer)) {
            revert InactiveOffer(listingId, buyer);
        }
        delete _offers[listingId][buyer];
        (bool success,) = msg.sender.call{value: offer.price}("");
        if (!success) {
            revert Unpaid(listingId, msg.sender, offer.price);
        }
        emit Accepted(listingId, buyer, offer.price);
    }
}
