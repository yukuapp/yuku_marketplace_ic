import Types "types";
import Utils "utils";
import Time "mo:base/Time";
import HashMap "mo:base/HashMap";
import Result "mo:base/Result";
import Nat "mo:base/Nat";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Hash "mo:base/Hash";
import Nat64 "mo:base/Nat64";
import Iter "mo:base/Iter";
import TrieSet "mo:base/TrieSet";
import Principal "mo:base/Principal";
import Ext "mo:ext/Ext";

module {
    type TokenIdentifier = Types.TokenIdentifier;
    type AccountIdentifier = Types.AccountIdentifier;
    type User = Types.User;

    public type NewFixed = {
        price : Price;
        tokenIdentifier : TokenIdentifier;
        token : TokenSpec;
    };
    public type TokenSpec = Types.TokenSpec;
    type Fixed = Types.Fixed;
    public type DutchAuction = Types.DutchAuction;
    type Auction = Types.Auction;
    type Fee = Types.Fee;
    type Listing = Types.Listing;
    type Price = Types.Price;
    public type OnAuction = {
        bidder : Principal;
        price : Price;
        tokenIdentifier : TokenIdentifier;
    };

    public type NewDutchAuction = {
        startPrice : Price;
        floorPrice : Price;
        startTime : Time.Time;
        endTime : Time.Time;
        reducePrice : Price;
        reduceTime : Nat64;
        payee : ?User;
        tokenIdentifier : TokenIdentifier; // tokenId
        token : TokenSpec;
    };
    type OfferStatus = {
        #ineffect;
        #rejected;
        #accepted;
        #expired;
    };
    public type NewOffer = {
        bidder : Principal;
        seller : User;
        price : Price;
        tokenIdentifier : TokenIdentifier;
        ttl : Int;
        token : TokenSpec;
    };

    public type Offer = {
        offerId : OfferId;
        bidder : Principal;
        seller : User;
        price : Price;
        ttl : Int;
        time : Time.Time;
        tokenIdentifier : TokenIdentifier;
        status : OfferStatus;
        token : TokenSpec;
    };

    type TradeType = {
        #fixed;
        #auction;
        #offer;
        #dutchAuction;
    };

    public type Order = {
        buyer : User;
        seller : User;
        tokenIdentifier : TokenIdentifier;
        price : Price;
        time : Int;
        tradeType : TradeType;
        fee : {
            platform : {fee:Nat64;precision:Nat64};
            royalties : {fee:Nat64;precision:Nat64};
        };
        memo : Nat64;
        token : TokenSpec;
    };

    public type Err = {
        #nftNotlist;
        #nftlockedByOther;
        #nftNotAuction;
        #auctionFail;
        #nftAlreadyListing;
        #notFoundOffer;
        #offerExpired;
        #kycNotPass;
        #amlNotPass;
        #kycorAmlNotPass;
        #other : (TokenIdentifier, Text);
        #msgandBidder : (Principal, Principal);
    };
    public type LockResult = Result.Result<(), Err>;
    public type OfferId = Types.OfferId;
    public type DutchAuctionId = Types.DutchAuctionId;
    public type TradeResult = Result.Result<Order, Err>;
    public type ListResult = Result.Result<TokenIdentifier, Err>;
    public type DutchAuctionResult = Result.Result<(), Err>;
    public type OfferResult = Result.Result<OfferId, Err>;
    public type BatchTradeResult = Result.Result<{ Memo : Nat; Price : Nat64 }, Err>; //batch tid

    public type TradeStable = {
        var tradeIndex : Nat;
        var offerIndex : Nat;
        var trades : [(Nat, Listing)];
        var fixeds : [(TokenIdentifier, Nat)];
        var offers : [(OfferId, Offer)];
        var offerMap : [(TokenIdentifier, [OfferId])];
        var offersByCollection : [(Principal, [TokenIdentifier])];
        var tokenIdentifieOffersHighest : [(TokenIdentifier, Offer)];
    };

    public func emptyTradeStable() : TradeStable {
        {
            var tradeIndex = 1;
            var offerIndex = 1;
            var trades = [];
            var fixeds = [];
            var offers = [];
            var offerMap = [];
            var offersByCollection = [];
            var tokenIdentifieOffersHighest = [];
        };
    };

    public class Trade() {
        //add TradeId
        private var tradeIndex : Nat = 1;
        var trades = HashMap.HashMap<Nat, Listing>(0, Nat.equal, Hash.hash);
        var fixeds = HashMap.HashMap<TokenIdentifier, Nat>(0, Types.TokenIdentifier.equal, Types.TokenIdentifier.hash);
        var batchfixeds = HashMap.HashMap<Nat, [TokenIdentifier]>(0, Nat.equal, Hash.hash);
        var offerMap = HashMap.HashMap<TokenIdentifier, [OfferId]>(0, Types.TokenIdentifier.equal, Types.TokenIdentifier.hash);
        var offers = HashMap.HashMap<OfferId, Offer>(0, Nat.equal, Hash.hash);
        var offersByCollection = HashMap.HashMap<Principal, [TokenIdentifier]>(0, Principal.equal, Principal.hash);
        var tokenIdentifieOffersHighest = HashMap.HashMap<TokenIdentifier, Offer>(0, Types.TokenIdentifier.equal, Types.TokenIdentifier.hash);

        private var offerIndex : Nat = 1;

        public func toStable(ts : TradeStable) {
            ts.tradeIndex := tradeIndex;
            ts.offerIndex := offerIndex;
            ts.trades := Iter.toArray(trades.entries());
            ts.fixeds := Iter.toArray(fixeds.entries());
            ts.offers := Iter.toArray(offers.entries());
            ts.offerMap := Iter.toArray(offerMap.entries());

            ts.offersByCollection := Iter.toArray(offersByCollection.entries());
            ts.tokenIdentifieOffersHighest := Iter.toArray(tokenIdentifieOffersHighest.entries());
        };

        public func fromStable(ts : TradeStable) {
            tradeIndex := ts.tradeIndex;
            offerIndex := ts.offerIndex;
            trades := HashMap.fromIter<Nat, Listing>(ts.trades.vals(), ts.trades.size(), Nat.equal, Hash.hash);
            fixeds := HashMap.fromIter<TokenIdentifier, Nat>(ts.fixeds.vals(), ts.fixeds.size(), Types.TokenIdentifier.equal, Types.TokenIdentifier.hash);
            offers := HashMap.fromIter<OfferId, Offer>(ts.offers.vals(), ts.offers.size(), Nat.equal, Hash.hash);
            offerMap := HashMap.fromIter<TokenIdentifier, [OfferId]>(ts.offerMap.vals(), ts.offerMap.size(), Types.TokenIdentifier.equal, Types.TokenIdentifier.hash);

            offersByCollection := HashMap.fromIter<Principal, [TokenIdentifier]>(ts.offersByCollection.vals(), ts.offersByCollection.size(), Principal.equal, Principal.hash);
            tokenIdentifieOffersHighest := HashMap.fromIter<TokenIdentifier, Offer>(ts.tokenIdentifieOffersHighest.vals(), ts.tokenIdentifieOffersHighest.size(), Types.TokenIdentifier.equal, Types.TokenIdentifier.hash);
        };

        public func batchFixedSablePre() : [(Nat, [TokenIdentifier])] {
            return Iter.toArray(batchfixeds.entries());
        };

        public func batchFixedSablePost(p : [(Nat, [TokenIdentifier])]) {
            for ((tid, tokenIdentifiers) in p.vals()) {
                batchfixeds.put(tid, tokenIdentifiers);
            };
        };

        public func getTradeInfo(tokenIdentifier : TokenIdentifier) : ?Listing {
            _getListing(tokenIdentifier);
        };

        public func getTradeInfoByTid(tid : Nat) : ?Listing {
            trades.get(tid);
        };
        public func getBatchTradeInfoByTid(tid : Nat) : [Listing] {
            let result = Buffer.Buffer<Listing>(0);
            switch (batchfixeds.get(tid)) {
                case (?tokenIdentifiers) {
                    for (tokenIdentifier in tokenIdentifiers.vals()) {
                        switch (_getListing(tokenIdentifier)) {
                            case (?listing) {
                                result.add(listing);
                            };
                            case _ {};
                        };
                    };

                };
                case _ {};
            };
            return result.toArray();
        };

        public func sellDutchAuction(auction : DutchAuction) : DutchAuctionResult {
            switch (fixeds.get(auction.tokenIdentifier)) {
                case (?tid) {
                    trades.put(tid, #dutchAuction(auction));
                };
                case _ {
                    let _tid = tradeIndex;
                    fixeds.put(auction.tokenIdentifier, _tid);
                    trades.put(_tid, #dutchAuction(auction));
                    tradeIndex += 1;
                };
            };
            #ok(());
        };
        public func sell(fixed : Fixed) : ListResult {
            _sell(fixed);
        };
        public func batchSell(fixeds : [Fixed]) : [ListResult] {
            let result = Buffer.Buffer<ListResult>(fixeds.size());
            for (fixed in fixeds.vals()) {
                result.add(_sell(fixed));
            };
            result.toArray();
        };

        func _sell(fixed : Fixed) : ListResult {
            if (fixed.price == 0) {
                return #err(#other(fixed.tokenIdentifier, "fixed price cant be zero"));
            };
            switch (fixeds.get(fixed.tokenIdentifier)) {
                case (?tid) {
                    trades.put(tid, #fixed(fixed));
                };
                case _ {
                    let _tid = tradeIndex;
                    fixeds.put(fixed.tokenIdentifier, _tid);
                    trades.put(_tid, #fixed(fixed));
                    tradeIndex += 1;
                };
            };
            #ok(fixed.tokenIdentifier);
        };

        public func newSell(fixed : Fixed) : ListResult {
            switch (fixeds.get(fixed.tokenIdentifier)) {
                case (?tid) {
                    return #err(#other(fixed.tokenIdentifier, "listing already exist"));
                };
                case _ {
                    let _tid = tradeIndex;
                    fixeds.put(fixed.tokenIdentifier, _tid);
                    trades.put(_tid, #fixed(fixed));
                    tradeIndex += 1;
                };
            };
            #ok(fixed.tokenIdentifier);
        };

        public func buyNow(tokenIdentifier : TokenIdentifier, buyer : Principal,royality : Types.Royality,platformFee : Types.PlatformFee) : TradeResult {
            switch (fixeds.get(tokenIdentifier)) {
                case (?tid) {
                    switch (trades.get(tid)) {
                        case (?(#fixed(fixed))) {
                            return #ok({
                                memo = Nat64.fromNat(tid);
                                buyer = #principal(buyer);
                                seller = #principal(fixed.seller);
                                tokenIdentifier = tokenIdentifier;
                                price = fixed.price;
                                time = Time.now();
                                tradeType = #fixed;
                                fee = {
                                   platform = {fee=platformFee.fee;precision=platformFee.precision};
                                   royalties = {fee=royality.rate;precision=royality.precision};
                                };
                                token = fixed.token;
                            });
                        };
                        case (?(#dutchAuction(dutchAuction))) {
                            // 价格需要前端自己算

                            return #ok({
                                memo = Nat64.fromNat(tid);
                                buyer = #principal(buyer);
                                seller = #principal(dutchAuction.seller);
                                tokenIdentifier = tokenIdentifier;
                                price = dutchAuction.startPrice;
                                time = Time.now();
                                tradeType = #dutchAuction;
                                fee = {
                                   platform = {fee=platformFee.fee;precision=platformFee.precision};
                                   royalties = {fee=royality.rate;precision=royality.precision};
                                };
                                token = dutchAuction.token;
                            });
                        };
                        case _ {
                            return #err(#nftNotlist);
                        };
                    };
                };
                case _ {
                    return #err(#nftNotlist);
                };
            };
        };

        public func batchBuyNow(tokenIdentifiers : [TokenIdentifier]) : BatchTradeResult {
            var _tokenIdentifiers = tokenIdentifiers;
            var price : Nat64 = 0;
            for (tokenIdentifier in tokenIdentifiers.vals()) {
                switch (fixeds.get(tokenIdentifier)) {
                    case (?tid) {
                        switch (trades.get(tid)) {
                            case (?(#fixed(fixed))) {
                                price += fixed.price;
                            };
                            case _ {
                                _tokenIdentifiers := Array.filter<TokenIdentifier>(_tokenIdentifiers, func(v) { v != tokenIdentifier });
                            };
                        };
                    };
                    case _ {
                        _tokenIdentifiers := Array.filter<TokenIdentifier>(_tokenIdentifiers, func(v) { v != tokenIdentifier });
                    };
                };
            };
            if (_tokenIdentifiers.size() > 0) {
                let _tid = tradeIndex;
                batchfixeds.put(_tid, _tokenIdentifiers);
                tradeIndex += 1;
                return #ok({
                    Memo = _tid;
                    Price = price;
                });
            } else {
                return #err(#nftNotlist);
            };
        };
        public func batchResetTrade(tid : Nat) {
            switch (batchfixeds.get(tid)) {
                case (?tokenIdentifiers) {
                    for (tokenIdentifier in tokenIdentifiers.vals()) {
                        resetTrade(tokenIdentifier);
                    };
                };
                case _ {};
            };
        };

        private func _getListing(tokenIdentifier : TokenIdentifier) : ?Listing {
            switch (fixeds.get(tokenIdentifier)) {
                case (?tid) {
                    trades.get(tid);
                };
                case _ { null };
            };
        };

        //offer
        public func makeOffer(newOffer : NewOffer) : OfferResult {
            let offerId = offerIndex;

            if (newOffer.price == 0) {
                return #err(#other(newOffer.tokenIdentifier, "Offer price cant be zero"));
            };

            let offer = {
                offerId = offerId;
                bidder = newOffer.bidder;
                seller = newOffer.seller;
                price = newOffer.price;
                tokenIdentifier = newOffer.tokenIdentifier;
                ttl = newOffer.ttl;
                time = Time.now();
                status = #ineffect;
                token = newOffer.token;
            };
            // Principal
            let tokenObj = Ext.TokenIdentifier.decode(newOffer.tokenIdentifier);
            let collectionId = Principal.fromText(tokenObj.canister);
            switch (offersByCollection.get(collectionId)) {
                case (?ids) {
                    // 记录一个collection下面有那个tid有offer
                    let exist = Utils.existIm<TokenIdentifier>(ids, func(v) { v == newOffer.tokenIdentifier });
                    if (exist == false) {
                        let newIds = Array.append(ids, Array.make(newOffer.tokenIdentifier));
                        offersByCollection.put(collectionId, newIds);
                    };
                };
                case _ {
                    offersByCollection.put(collectionId, Array.make(newOffer.tokenIdentifier));
                };
            };
            // 更新最高价
            switch (tokenIdentifieOffersHighest.get(newOffer.tokenIdentifier)) {
                case (?oldOffer) {
                    if (oldOffer.price <= newOffer.price) {
                        tokenIdentifieOffersHighest.put(newOffer.tokenIdentifier, offer);
                    };
                };
                case _ {
                    tokenIdentifieOffersHighest.put(newOffer.tokenIdentifier, offer);
                };
            };

            offers.put(offerId, offer);
            offerIndex += 1;
            switch (offerMap.get(offer.tokenIdentifier)) {
                case (?ids) {
                    let offerIds = Array.append(ids, Array.make(offerId));
                    offerMap.put(offer.tokenIdentifier, offerIds);
                };
                case _ {
                    offerMap.put(offer.tokenIdentifier, Array.make(offerId));
                };
            };
            #ok((offerId));
        };

        public func updateOffer(offerId : OfferId, price : Price, caller : Principal) : Bool {
            let offer = Utils.unwrap(offers.get(offerId));

            if (price == 0) {
                return false;
            };

            if (offer.bidder != caller) {
                return false;
            };
            switch (offer.status) {
                case (#rejected) {
                    return false;
                };
                case (#accepted) {
                    return false;
                };
                case _ {};
            };
            offers.put(
                offerId,
                {
                    offerId = offer.offerId;
                    bidder = offer.bidder;
                    seller = offer.seller;
                    price = price;
                    tokenIdentifier = offer.tokenIdentifier;
                    ttl = offer.ttl;
                    time = Time.now();
                    status = offer.status;
                    token = offer.token;
                },
            );

            var offerIds = Utils.unwrap(offerMap.get(offer.tokenIdentifier));
            switch (tokenIdentifieOffersHighest.get(offer.tokenIdentifier)) {
                case (?highOffer) {
                    if (highOffer.offerId == offerId or price >= highOffer.price) {
                        tokenIdentifieOffersHighest.delete(highOffer.tokenIdentifier);
                        switch (_calcHighestOffer(offerIds)) {
                            case (?newHighOffer) {
                                tokenIdentifieOffersHighest.put(offer.tokenIdentifier, newHighOffer);
                            };
                            case _ {};
                        };
                    };
                };
                case _ {

                };
            };
            true;
        };

        public func acceptOffer(offerId : OfferId, seller : User) : Result.Result<Offer, Text> {
            let offer = Utils.unwrap(offers.get(offerId));
            let requestSeller = Ext.User.toAID(seller);
            let offerSeller = Ext.User.toAID(offer.seller);
            if (requestSeller != offerSeller) {
                return #err("Not Offer Seller");
            };

            switch (offer.status) {
                case (#rejected) {
                    return #err("Offer Already Rejected");
                };
                case (#accepted) {
                    return #err("Offer Already Accepted");
                };
                case _ {};
            };
            if (Time.now() > offer.ttl) {
                return #err("Offer has expired");
            };
            let newOffer = {
                offerId = offerId;
                bidder = offer.bidder;
                seller = offer.seller;
                price = offer.price;
                ttl = offer.ttl;
                time = offer.time;
                tokenIdentifier = offer.tokenIdentifier;
                status = #accepted;
                token = offer.token;
            };
            offers.put(offerId, newOffer);

            var offerIds = Utils.unwrap(offerMap.get(offer.tokenIdentifier));
            switch (tokenIdentifieOffersHighest.get(offer.tokenIdentifier)) {
                case (?highOffer) {
                    if (highOffer.offerId == offerId) {
                        tokenIdentifieOffersHighest.delete(offer.tokenIdentifier);
                        switch (_calcHighestOffer(offerIds)) {
                            case (?newHighOffer) {
                                tokenIdentifieOffersHighest.put(offer.tokenIdentifier, newHighOffer);
                            };
                            case _ {};
                        };
                    };
                };
                case _ {

                };
            };
            return #ok(newOffer);
        };

        public func rejectOffer(offerId : OfferId, seller : User) : Result.Result<(), Text> {
            let offer = Utils.unwrap(offers.get(offerId));

            let requestSeller = Ext.User.toAID(seller);
            let offerSeller = Ext.User.toAID(offer.seller);
            if (requestSeller != offerSeller) {
                return #err("Not Offer Seller");
            };

            switch (offer.status) {
                case (#rejected) {
                    return #err("Offer Already Rejected");
                };
                case (#accepted) {
                    return #err("Offer Already Accepted");
                };
                case _ {};
            };
            let newOffer = {
                offerId = offerId;
                bidder = offer.bidder;
                seller = offer.seller;
                price = offer.price;
                ttl = offer.ttl;
                time = offer.time;
                tokenIdentifier = offer.tokenIdentifier;
                status = #rejected;
                token = offer.token;
            };
            offers.put(offerId, newOffer);

            var offerIds = Utils.unwrap(offerMap.get(offer.tokenIdentifier));
            switch (tokenIdentifieOffersHighest.get(offer.tokenIdentifier)) {
                case (?highOffer) {
                    if (highOffer.offerId == offerId) {
                        tokenIdentifieOffersHighest.delete(offer.tokenIdentifier);
                        switch (_calcHighestOffer(offerIds)) {
                            case (?newHighOffer) {
                                tokenIdentifieOffersHighest.put(offer.tokenIdentifier, newHighOffer);
                            };
                            case _ {};
                        };
                    };
                };
                case _ {

                };
            };
            return #ok();
        };

        public func rejectOfferByUser(offerId : OfferId, userYumi : User) : Result.Result<(), Text> {
            let offer = Utils.unwrap(offers.get(offerId));

            let requestUser = Ext.User.toAID(userYumi);
            let offerBidder = Ext.User.toAID(#principal(offer.bidder));
            if (requestUser != offerBidder) {
                return #err("Not Offer Bidder");
            };

            switch (offer.status) {
                case (#rejected) {
                    return #err("Offer Already Rejected");
                };
                case (#accepted) {
                    return #err("Offer Already Accepted");
                };
                case _ {};
            };
            let newOffer = {
                offerId = offerId;
                bidder = offer.bidder;
                seller = offer.seller;
                price = offer.price;
                ttl = offer.ttl;
                time = offer.time;
                tokenIdentifier = offer.tokenIdentifier;
                status = #rejected;
                token = offer.token;
            };
            offers.put(offerId, newOffer);

            var offerIds = Utils.unwrap(offerMap.get(offer.tokenIdentifier));
            switch (tokenIdentifieOffersHighest.get(offer.tokenIdentifier)) {
                case (?highOffer) {
                    if (highOffer.offerId == offerId) {
                        tokenIdentifieOffersHighest.delete(offer.tokenIdentifier);
                        switch (_calcHighestOffer(offerIds)) {
                            case (?newHighOffer) {
                                tokenIdentifieOffersHighest.put(offer.tokenIdentifier, newHighOffer);
                            };
                            case _ {};
                        };
                    };
                };
                case _ {

                };
            };
            return #ok();
        };

        public func expiredOffer(offerId : OfferId) {
            let offer = Utils.unwrap(offers.get(offerId));
            switch (offer.status) {
                case (#ineffect) {
                    if (Time.now() > offer.ttl) {
                        let newOffer = {
                            offerId = offerId;
                            bidder = offer.bidder;
                            seller = offer.seller;
                            price = offer.price;
                            ttl = offer.ttl;
                            time = offer.time;
                            tokenIdentifier = offer.tokenIdentifier;
                            status = #expired;
                            token = offer.token;
                        };
                        offers.put(offerId, newOffer);
                    };
                };
                case _ {};
            };

        };

        public func findHighOfferByNft(tokenIdentifier : TokenIdentifier) : ?Offer {
            switch (tokenIdentifieOffersHighest.get(tokenIdentifier)) {
                case (?offer) {
                    return ?offer;
                };
                case _ {
                    return null;
                };
            };
        };

        public func findOfferByNft(tokenIdentifier : TokenIdentifier) : [Offer] {
            let offersBuf = Buffer.Buffer<Offer>(0);
            switch (offerMap.get(tokenIdentifier)) {
                case (?ids) {
                    for (id in ids.vals()) {
                        let offer = Utils.unwrap(offers.get(id));
                        offersBuf.add(offer);
                    };
                };
                case _ {};
            };
            offersBuf.toArray();
        };

        public func findOfferById(offerId : OfferId) : ?Offer {
            offers.get(offerId);
        };

        public func getOfferTids() : [TokenIdentifier] {
            return Iter.toArray(offerMap.keys());
        };

        public func cancelOffer(offerId : OfferId) {
            let offer = Utils.unwrap(offers.get(offerId));
            offers.delete(offerId);
            var offerIds = Utils.unwrap(offerMap.get(offer.tokenIdentifier));
            offerIds := Array.filter<OfferId>(offerIds, func(v) { v != offerId });
            offerMap.put(offer.tokenIdentifier, offerIds);

            let tokenObj = Ext.TokenIdentifier.decode(offer.tokenIdentifier);
            let collectionId = Principal.fromText(tokenObj.canister);

            if (offerIds.size() == 0) {
                offersByCollection.delete(collectionId);
                tokenIdentifieOffersHighest.delete(offer.tokenIdentifier);
            };

            switch (tokenIdentifieOffersHighest.get(offer.tokenIdentifier)) {
                case (?highOffer) {
                    if (highOffer.offerId == offerId) {
                        tokenIdentifieOffersHighest.delete(offer.tokenIdentifier);
                        switch (_calcHighestOffer(offerIds)) {
                            case (?newHighOffer) {
                                tokenIdentifieOffersHighest.put(offer.tokenIdentifier, newHighOffer);
                            };
                            case _ {};
                        };
                    };
                };
                case _ {

                };
            };
        };

        private func _calcHighestOffer(offerIds : [OfferId]) : ?Offer {
            var price : Price = 0;
            var highestOfferId : OfferId = 0;
            label inner for (id in offerIds.vals()) {
                switch (offers.get(id)) {
                    case (?offer) {
                        switch (offer.status) {
                            case (#ineffect) {
                                if (price < offer.price) {
                                    price := offer.price;
                                    highestOfferId := offer.offerId;
                                };
                                if (price == offer.price and offer.time < Utils.unwrap(offers.get(highestOfferId)).time) {
                                    highestOfferId := offer.offerId;
                                };
                            };
                            case _ {
                                continue inner;
                            };
                        };
                    };
                    case _ {};
                };
            };

            return offers.get(highestOfferId);
        };


        public func resetTrade(tokenIdentifier : TokenIdentifier) {
            switch (fixeds.get(tokenIdentifier)) {
                case (?tid) {
                    trades.delete(tid);
                };
                case _ {};
            };
            fixeds.delete(tokenIdentifier);
        };


    };
};
