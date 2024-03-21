import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Cycles "mo:base/ExperimentalCycles";
import Float "mo:base/Float";
import Hash "mo:base/Hash";
import HashMap "mo:base/HashMap";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Option "mo:base/Option";
import Order "mo:base/Order";
import P "mo:base/Prelude";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Time "mo:base/Time";
import TrieMap "mo:base/TrieMap";
import TrieSet "mo:base/TrieSet";
import AIDHex "mo:crypto/Hex";
import Hex "mo:encoding/Hex";
import Ext "mo:ext/Ext";
import AccountIdentifier "mo:principal/AccountIdentifier";
import AviateAID "mo:principal/blob/AccountIdentifier";
import Canistergeek "mo:canistergeek/canistergeek";

import Utils "utils";
import Ledger "ledger";
import LedgerInterface "ledgerInterface";
import Collection "ERC721";
import Trade "trade";
import Types "types";

shared actor class Platform(owner : Principal, platformFeeAccount : Principal) = this {
    type AccountIdentifier = Types.AccountIdentifier;
    type TokenIdentifier = Types.TokenIdentifier;
    type TransferRequest = Types.TransferRequest;
    type TransferResponse = Types.TransferResponse;
    type User = Types.User;
    type TokenSpec = Types.TokenSpec;
    type Price = Types.Price;
    type PageParam = Types.PageParam;

    private stable var _owner : Principal = owner;
    public shared (msg) func setOwner(owner : Principal) : async () {
        assert (msg.caller == _owner);
        _owner := owner;
    };

    public shared (msg) func getOwner() : async Principal {
        _owner;
    };

    // receive icp account
    stable var platformFee : Types.PlatformFee = {
        var fee = 3;
        var account = platformFeeAccount;
        var precision = 2;
    };

    public shared (msg) func setPlatformAccount(account : Principal) : async () {
        assert (msg.caller == _owner);
        platformFee.account := account;
    };

    public shared (msg) func setPlatformFee(fee : Nat64, precision : Nat64) : async () {
        assert (msg.caller == _owner);
        platformFee.fee := fee;
        platformFee.precision := precision;
    };

    public query func queryPlatformFee() : async {
        fee : Price;
        account : AccountIdentifier;
        precision : Nat64;
    } {
        {
            fee = platformFee.fee;
            account = Types.AccountIdentifier.fromPrincipal(platformFee.account, null);
            precision = platformFee.precision;
        };
    };

    private stable var pointRatio : Nat64 = 3;

    public shared (msg) func setPointRatio(newRatio : Nat64) : async () {
        assert (msg.caller == _owner);
        pointRatio := newRatio;
    };

    public query func queryPointRatio() : async Nat64 {
        pointRatio;
    };

    func _hashNat(ids : Nat) : Hash.Hash {
        Hash.hash(ids);
    };

    ///collection
    type CollectionInfo = Types.CollectionInfo;
    type CollectionInit = Types.CollectionInit;
    type CollectionErr = Types.CollectionErr;
    type Collection = Types.Collection;

    private var maxCollNum : Nat = 0;
    private var perMaxCollNum : Nat = 1;
    private var eachTokenCycles : Nat = 2000000000000;


    private stable var _collectionArray : [(Principal, CollectionInfo)] = [];
    private var _collections = HashMap.fromIter<Principal, CollectionInfo>(_collectionArray.vals(), _collectionArray.size(), Principal.equal, Principal.hash);

    private stable var creator_whitelist : [Principal] = [];
    private stable var second_creator_whitelist : [Principal] = [];

    public shared (msg) func addCreator_whitelist(whitelist : [Principal]) : async () {
        assert (msg.caller == _owner);
        creator_whitelist := Array.append(creator_whitelist, whitelist);
    };

    public shared (msg) func delCreator_whitelist(whitelists : [Principal]) : async () {
        assert (msg.caller == _owner);
        for (whitelist in whitelists.vals()) {
            creator_whitelist := Array.filter<Principal>(creator_whitelist, func(v) { v != whitelist });
        };
    };

    public shared (msg) func addSecond_creator_whitelist(whitelist : [Principal]) : async () {
        assert (Utils.existIm<Principal>(creator_whitelist, func(v) { v == msg.caller }));
        second_creator_whitelist := Array.append(second_creator_whitelist, whitelist);
    };

    public shared (msg) func delSecond_creator_whitelist(whitelists : [Principal]) : async () {
        assert (Utils.existIm<Principal>(creator_whitelist, func(v) { v == msg.caller }));
        for (whitelist in whitelists.vals()) {
            second_creator_whitelist := Array.filter<Principal>(second_creator_whitelist, func(v) { v != whitelist });
        };
    };

    public query (msg) func getCreator_whitelist() : async [Principal] {
        creator_whitelist;
    };
    public query (msg) func getSecond_creator_whitelist() : async [Principal] {
        second_creator_whitelist;
    };
    public shared (msg) func createCollection(init : CollectionInit) : async Result.Result<Principal, CollectionErr> {
        assert (Utils.existIm<Principal>(creator_whitelist, func(v) { v == msg.caller }) or Utils.existIm<Principal>(second_creator_whitelist, func(v) { v == msg.caller }));
        Cycles.add(eachTokenCycles);
        let collection : Collection = await Collection.ERC721(msg.caller);
        let c = Principal.fromActor(collection);
        let creator = msg.caller;
        let collectionInfo = makeCollectionInfo(init, c, creator);
        _collections.put(c, collectionInfo);
        #ok(c);
    };

    private func makeCollectionInfo(init : CollectionInit,collection : Principal, creator : Types.UserId) : CollectionInfo {
        {
            name = init.name;
            logo = init.logo;
            banner = init.banner;
            featured = init.featured;
            description = init.description;
            url = init.url;
            category = init.category;
            royalties = init.royalties;
            links = init.links;
            canisterId = collection;
            releaseTime = init.releaseTime;
            isVisible = init.isVisible;
            creator = creator;
            standard = init.standard;
        };
    };

    func _getCollectionInfo(id : Principal) : ?CollectionInfo {
        switch (_collections.get(id)) {
            case (?info) {
                if (not info.isVisible) {
                    return null;
                };
                ?info
            };
            case _ {
                return null;
            };
        };
    };

    public query func getCollectionData(id : Principal) : async ?CollectionInfo {
        _getCollectionInfo(id);
    };

    public query func getCollectionDatas(ids : [Principal]) : async [CollectionInfo] {
        let result = Buffer.Buffer<CollectionInfo>(ids.size());
        for (id in ids.vals()) {
            switch (_getCollectionInfo(id)) {
                case (?collectionData) {
                    result.add(collectionData);
                };
                case _ {};
            };
        };
        result.toArray();
    };

    public query func listCollections() : async [Text] {
        let collectionList = Buffer.Buffer<Text>(_collections.size());
        for (canisterId in Iter.toArray(_collections.keys()).vals()) {
            collectionList.add(Principal.toText(canisterId));
        };
        collectionList.toArray();
    };

    public shared (msg) func importCollection(target : Principal, c : Text, init : CollectionInit) : async Result.Result<(), CollectionErr> {
        assert (Utils.existIm<Principal>(creator_whitelist, func(v) { v == msg.caller }));
        let collection = Principal.fromText(c);
        let collectionInfo = makeCollectionInfo(init, collection, target);
        switch (_collections.get(collection)) {
            case (?info) {
                let erc721 : Collection = actor(Principal.toText(info.canisterId));
                let minter = await erc721.getMinter();
                assert (minter == msg.caller or Utils.existIm<Principal>(creator_whitelist, func(v) { v == msg.caller }));
                switch (_collections.get(info.canisterId)) {
                    case (?collectionInfo) {
                        _collections.put(
                            info.canisterId,
                            {
                                name = init.name;
                                logo = init.logo;
                                banner = init.banner;
                                featured = init.featured;
                                url = init.url;
                                description = init.description;
                                category = init.category;
                                links = init.links;
                                royalties = init.royalties;
                                canisterId = info.canisterId;
                                releaseTime = init.releaseTime;
                                isVisible = init.isVisible;
                                creator = info.creator;
                                standard = info.standard;
                            },
                        );
                    };
                    case _ {};
                };
                return #ok(());
            };
            case _ {};
        };
        _collections.put(collection, collectionInfo);
        #ok(());
    };

    public shared (msg) func removeCollection(target : Principal, c : Text) : async Result.Result<(), CollectionErr> {
        assert (Utils.existIm<Principal>(creator_whitelist, func(v) { v == msg.caller }));
        let collection = Principal.fromText(c);
        switch (_collections.get(collection)) {
            case (?collectionInfo) {
                _collections.delete(collection);
            };
            case _ {};
        };
        #ok(());
    };

    //trade
    let trade = Trade.Trade();
    type TradeResult = Trade.TradeResult;
    type ListResult = Trade.ListResult;
    type DutchAuctionResult = Trade.DutchAuctionResult;

    private func _nftInfo(tokenIdentifier : TokenIdentifier) : Types.NFTInfo {
        var _listing : Types.Listing = #unlist;
        switch (trade.getTradeInfo(tokenIdentifier)) {
            case (?listing) {
                _listing := listing;
            };
            case _ {};
        };
        return {
            views = 0;
            lastPrice = 0;
            favoriters = [];
            listing = _listing;
            listTime = null;
        };
    };

    public query func nftInfo(tokenIdentifier : TokenIdentifier) : async Types.NFTInfo {
        _nftInfo(tokenIdentifier);
    };

    public query func nftInfos(tokenIdentifiers : [TokenIdentifier]) : async [Types.NFTInfo] {
        var buff = Buffer.Buffer<Types.NFTInfo>(0);
        for (tokenIdentifier in tokenIdentifiers.vals()) {
            buff.add(_nftInfo(tokenIdentifier));
        };
        buff.toArray();
    };

    public query func nftInfosByCollectionPageable(collection : Principal, pageParam : PageParam) : async [Types.NFTInfo] {
        var buff = Buffer.Buffer<Types.NFTInfo>(0);
        let start : Nat = (pageParam.page - 1) * pageParam.pageCount;
        let end : Nat = start + pageParam.pageCount - 1;
        for (i in Iter.range(start, end)) {
            let tokenIdentifier = Utils.encode(collection, Nat32.fromNat(i));
            buff.add(_nftInfo(tokenIdentifier));
        };
        buff.toArray();
    };

    public query func nftInfosByCollection(collection : Principal, tokenIndexs : [Nat32]) : async [Types.NFTInfo] {
        var buff = Buffer.Buffer<Types.NFTInfo>(0);
        for (tokenIndex in tokenIndexs.vals()) {
            let tokenIdentifier = Utils.encode(collection, tokenIndex);
            buff.add(_nftInfo(tokenIdentifier));
        };
        buff.toArray();
    };



    public shared (msg) func sellDutchAuction(auction : Trade.NewDutchAuction) : async DutchAuctionResult {
        let collectionId = Principal.fromText(Types.TokenIdentifier.getCollectionId(auction.tokenIdentifier));
        let isOwner : Bool = await checkOwner(auction.tokenIdentifier, #principal(msg.caller));
        if (isOwner) {
            let collectionInfo = switch (_collections.get(collectionId)) {
                case (?info) {
                    info;
                };
                case _ {
                    return #err(#other(auction.tokenIdentifier, "Collection Not Found!"));
                };
            };

            switch (collectionInfo.releaseTime) {
                case (?releaseTime) {
                    if (releaseTime > Time.now()) {
                        return #err(#other(auction.tokenIdentifier, "Collection still not release!"));
                    };
                };
                case _ {};
            };

            // _handleEvent
            if (Time.now() > auction.startTime) {
                return #err(#other(auction.tokenIdentifier, "Wrong auction start time"));
            };
            let payee = switch (auction.payee) {
                case (?payee) {
                    payee;
                };
                case _ {
                    #principal(msg.caller);
                };
            };
            trade.sellDutchAuction({
                startPrice = auction.startPrice;
                startTime = auction.startTime;
                endTime = auction.endTime;
                seller = msg.caller;
                payee = payee;
                reducePrice = auction.reducePrice;
                reduceTime = auction.reduceTime;
                floorPrice = auction.floorPrice;
                fee = {
                    platform = platformFee.fee;
                    royalties = collectionInfo.royalties.rate;
                };
                tokenIdentifier = auction.tokenIdentifier;
                token = auction.token;
            });

        } else {
            #err(#other(auction.tokenIdentifier, "NFT not own caller!"));
        };
    };

    public shared (msg) func sell(newFixed : Trade.NewFixed) : async ListResult {
        let listResults = await _sell([newFixed], msg.caller);
        listResults[0];
    };

    public shared (msg) func batchSell(newFixeds : [Trade.NewFixed]) : async [ListResult] {
        await _sell(newFixeds, msg.caller);
    };

    func _sell(newFixeds : [(Trade.NewFixed)], caller : Principal) : async [ListResult] {
        let result = Buffer.Buffer<ListResult>(newFixeds.size());
        let onwer_buffer = Buffer.Buffer<(Trade.NewFixed, async Bool)>(newFixeds.size());
        for (newFixed in newFixeds.vals()) {
            var isOwner = checkOwner(newFixed.tokenIdentifier, #principal(caller));
            onwer_buffer.add(newFixed, isOwner);
        };
        label c for ((newFixed, isOwner) in onwer_buffer.vals()) {
            let _isOwner = await isOwner;
            let collectionId = Principal.fromText(Types.TokenIdentifier.getCollectionId(newFixed.tokenIdentifier));
            if (_isOwner) {
                let collectionInfo : CollectionInfo = switch (_collections.get(collectionId)) {
                    case (?info) {
                        info;
                    };
                    case _ {
                        result.add(#err(#other(newFixed.tokenIdentifier, "Collection Not Found!")));
                        continue c;
                    };
                };
                switch (collectionInfo.releaseTime) {
                    case (?releaseTime) {
                        if (releaseTime > Time.now()) {
                            result.add(#err(#other(newFixed.tokenIdentifier, "Collection still not release!")));
                            continue c;
                        };
                    };
                    case _ {};
                };
                result.add(trade.sell({ price = newFixed.price; seller = caller; fee = { platform = platformFee.fee; royalties = collectionInfo.royalties.rate }; tokenIdentifier = newFixed.tokenIdentifier; token = newFixed.token }));
            } else {
                result.add(#err(#other(newFixed.tokenIdentifier, "NFT not own caller!")));
                continue c;
            };
        };
        result.toArray();
    };

    public shared (msg) func unSell(tokenIdentifier : TokenIdentifier) : async ListResult {
        let isOwner : Bool = await checkOwner(tokenIdentifier, #principal(msg.caller));
        if (isOwner) {
            let collectionId = Types.TokenIdentifier.getCollectionId(tokenIdentifier);
            trade.resetTrade(tokenIdentifier);
            #ok(tokenIdentifier);
        } else {
            #err(#other(tokenIdentifier, "NFT not own caller!"));
        };
    };

    //cart
    type AddCart = Types.AddCart;
    type ShowCart = Types.ShowCart;
    func _addCarthash(cart : AddCart) : Hash.Hash {
        Text.hash(cart.tokenIdentifier);
    };
    func _addCartequal(t1 : AddCart, t2 : AddCart) : Bool {
        t1.tokenIdentifier == t2.tokenIdentifier;
    };

    stable var _cartsState : [(Principal, [AddCart])] = [];
    var _carts : TrieMap.TrieMap<Principal, [AddCart]> = TrieMap.fromEntries(_cartsState.vals(), Principal.equal, Principal.hash);
    public shared (msg) func addCarts(tokens : [AddCart]) : async [Result.Result<TokenIdentifier, (TokenIdentifier, Text)>] {
        var result = Buffer.Buffer<Result.Result<TokenIdentifier, (TokenIdentifier, Text)>>(0);
        var tokenSet = TrieSet.empty<AddCart>();
        label c for (token in tokens.vals()) {
            switch (trade.getTradeInfo(token.tokenIdentifier)) {
                case (? #fixed(_)) {
                    tokenSet := TrieSet.put<AddCart>(tokenSet, token, _addCarthash(token), _addCartequal);
                    result.add(#ok(token.tokenIdentifier));
                };
                case _ {
                    result.add(#err(token.tokenIdentifier, "Token Not listing"));
                    continue c;
                };
            };
        };
        switch (_carts.get(msg.caller)) {
            case (?tokens) {
                var set = TrieSet.fromArray<AddCart>(tokens, _addCarthash, _addCartequal);
                tokenSet := TrieSet.union<AddCart>(set, tokenSet, _addCartequal);
                _carts.put(msg.caller, TrieSet.toArray<AddCart>(tokenSet));
            };
            case _ {
                _carts.put(msg.caller, TrieSet.toArray<AddCart>(tokenSet));
            };
        };
        result.toArray();
    };

    public shared (msg) func removeCarts(token : ?TokenIdentifier) : async () {
        switch (token) {
            case (?tokenIdentifier) {
                _removeCarts(msg.caller, tokenIdentifier);
            };
            case _ {
                _carts.delete(msg.caller);
            };
        };
    };

    func _removeCarts(caller : Principal, tokenIdentifier : TokenIdentifier) {
        switch (_carts.get(caller)) {
            case (?tokens) {
                _carts.put(caller, Array.filter<AddCart>(tokens, func(v) { v.tokenIdentifier != tokenIdentifier }));
            };
            case _ {};
        };
    };
    
    public shared (msg) func showCart() : async [ShowCart] {
        let result = Buffer.Buffer<Types.ShowCart>(0);
        switch (_carts.get(msg.caller)) {
            case (?tokens) {
                label c for (token in tokens.vals()) {
                    let collectionId = Principal.fromText(Types.TokenIdentifier.getCollectionId(token.tokenIdentifier));

                    let collectionInfo = switch (_collections.get(collectionId)) {
                        case (?info) {
                            info;
                        };
                        case _ {
                            continue c;
                        };
                    };
                    switch (trade.getTradeInfo(token.tokenIdentifier)) {
                        case (? #fixed(fixed)) {
                            result.add({
                                tokenIdentifier = token.tokenIdentifier;
                                collectionName = collectionInfo.name;
                                price = fixed.price;
                                nftName = token.nftName;
                                nftUrl = token.nftUrl;
                            });
                        };
                        case _ {
                            result.add({
                                tokenIdentifier = token.tokenIdentifier;
                                collectionName = collectionInfo.name;
                                price = 0;
                                nftName = token.nftName;
                                nftUrl = token.nftUrl;
                            });
                        };
                    };

                };
            };
            case _ {};
        };
        result.toArray();
    };

    public shared (msg) func batchBuyNow(tokenIdentifiers : [TokenIdentifier]) : async Trade.BatchTradeResult {
        let buffer = Buffer.Buffer<TokenIdentifier>(0);
        for (tokenIdentifier in tokenIdentifiers.vals()) {
            let collectionId = Principal.fromText(Types.TokenIdentifier.getCollectionId(tokenIdentifier));
            switch (_collections.get(collectionId)) {
                case (?info) {
                    switch (info.releaseTime) {
                        case (?releaseTime) {
                            if (releaseTime < Time.now()) {
                                buffer.add(tokenIdentifier);
                            };
                        };
                        case _ {
                            buffer.add(tokenIdentifier);
                        };
                    };
                };
                case _ {};
            };
        };
        let result = trade.batchBuyNow(buffer.toArray());
        return result;
    };
    public shared (msg) func buyNow(tokenIdentifier : TokenIdentifier) : async TradeResult {
        await _buyNow(tokenIdentifier, msg.caller);
    };

    func _buyNow(tokenIdentifier : TokenIdentifier, caller : Principal) : async TradeResult {
        let collectionId = Principal.fromText(Types.TokenIdentifier.getCollectionId(tokenIdentifier));
        let collectionInfo = switch (_collections.get(collectionId)) {
            case (?info) {
                info;
            };
            case _ {
                return #err(#other(tokenIdentifier, "Collection Not Found!"));
            };
        };
        switch (collectionInfo.releaseTime) {
            case (?releaseTime) {
                if (releaseTime > Time.now()) {
                    return #err(#other(tokenIdentifier, "Collection still not release!"));
                };
            };
            case _ {};
        };
        let result = trade.buyNow(tokenIdentifier, caller,collectionInfo.royalties,platformFee);
        return result;
    };

    private stable var transferIndex : Nat64 = 0;
    type Err = {
        #Unauthorized : AccountIdentifier;
        #InsufficientBalance;
        #Rejected;
        #InvalidToken : TokenIdentifier;
        #CannotNotify : AccountIdentifier;
        #Other : Text;
        #VerifyTxErr;
        #NotList;
        #NotSell;
        #TxNotFound;
        #DuplicateHeight;
    };
    type VerifyResult = Result.Result<TokenIdentifier, Err>;
    type BatchVerifyResult = Result.Result<[TokenIdentifier], Err>;

    private func _hash(h : Nat64) : Hash.Hash {
        Nat32.fromNat(Nat64.toNat(h));
    };

    public shared (msg) func batchVerifyTx(height : Nat64) : async BatchVerifyResult {
        var retrade = true;
        var refund : Nat64 = 0;
        var error : ?Err = null;
        let tokenIdentifiers = Buffer.Buffer<TokenIdentifier>(0);
        let transaction = await LedgerInterface.query_blocks(Ledger.ID,height);
        let toAID = AviateAID.toText(AviateAID.fromPrincipal(Principal.fromActor(this), null));
        let icpSettlments = TrieMap.TrieMap<User, Nat64>(Types.User.equal, Types.User.hash);
        var memo : Nat64 = 0;
        switch(transaction){
            case (?tx){
               switch (tx.operation) {
                    case (? #Transfer(transfer)) {
                        let from = AIDHex.encode(transfer.from);
                        let transferTo = AIDHex.encode(transfer.to);
                        if (not Hex.equal(transferTo, toAID)) {
                            return #err(#Unauthorized(transferTo));
                        };
                        memo := tx.memo;
                        let listings = trade.getBatchTradeInfoByTid(Nat64.toNat(memo));
                        canistergeekLogger.logMessage(
                            "\nfunc_name: batchVerifyTx" #
                            "\nlistings:" #debug_show (listings) # "\n\n"
                        );
                        if (listings.size() > 0) {
                            let transferResponse_buffer = Buffer.Buffer<(Types.Fixed, async TransferResponse, User)>(listings.size());
                            var totalPrice : Nat64 = 0;
                            label c for (listing in listings.vals()) {
                                switch (listing) {
                                    case (#fixed(fixed)) {
                                        let tokenIdentifier = fixed.tokenIdentifier;
                                        var to : User = #address(from);
                                        let collection = Types.TokenIdentifier.getCollectionId(tokenIdentifier);
                                        let erc721 : Collection = actor(collection);
                                        let transferResponse = erc721.transfer({
                                            from = #principal(fixed.seller);
                                            to = to;
                                            token = tokenIdentifier;
                                            amount = 1;
                                            memo = Blob.fromArray([]);
                                            notify = false;
                                            subaccount = null;
                                        });
                                        let creator = await _getCreator(Principal.fromText(collection));
                                        transferResponse_buffer.add(fixed, transferResponse, creator);
                                        totalPrice += fixed.price; //添加总金额
                                    };
                                    case _ {
                                        break c;
                                    };
                                };
                            };
                            if (totalPrice != transfer.amount.e8s) {
                                refund := transfer.amount.e8s;
                                error := ? #InsufficientBalance;
                            } else {
                                label c for ((fixed, item, creater) in transferResponse_buffer.vals()) {
                                    let transferResponse = await item;
                                    let _creater = creater;
                                    canistergeekLogger.logMessage(
                                        "\nfunc_name: batchVerifyTx" #
                                        "\ntransfer_reponse:" #debug_show (transferResponse) #
                                        "\nfixed:" #debug_show (fixed) # "\n\n"
                                    );
                                    switch (transferResponse) {
                                        case (#ok(ok)) {
                                            let collection = Types.TokenIdentifier.getCollectionId(fixed.tokenIdentifier);
                                            let royality = _getRoyalities(Principal.fromText(collection));
                                            let royalties = Nat64.div(fixed.price * royality.rate, Nat64.pow(10,royality.precision));
                                            let platformFees = Nat64.div(fixed.price * platformFee.fee, 100);
                                            let amount = fixed.price - royalties - platformFees;
                                            func _addICPSettlment(user : User, amount : Nat64) {
                                                switch (icpSettlments.get(user)) {
                                                    case (?_amount) {
                                                        icpSettlments.put(user, _amount + amount);
                                                    };
                                                    case _ {
                                                        icpSettlments.put(user, amount);
                                                    };
                                                };
                                            };
                                            _addICPSettlment(#principal(fixed.seller), amount);
                                            _addICPSettlment(#principal(platformFee.account), platformFees);
                                            _addICPSettlment(_creater, royalties);
                                            var to : ?Principal = null;
                                            if (Types.AccountIdentifier.fromPrincipal(msg.caller, null) == from) {
                                                to := ?msg.caller;
                                                retrade := false;
                                            };
                                            canistergeekLogger.logMessage(
                                                "\nfunc_name: #sold 1634 " #
                                                "\nto:" #debug_show (to) #
                                                "\ntoAID:" #debug_show (from) #
                                                "\ncorrectAID:" #debug_show (to) #
                                                "\n\n"
                                            );
                                            tokenIdentifiers.add(fixed.tokenIdentifier);
                                        };
                                        case (#err(err)) {
                                            refund += fixed.price;
                                            continue c;
                                        };
                                    };
                                };
                            };
                        } else {
                            refund := transfer.amount.e8s;
                            error := ? #NotList;
                        };
                        if (refund != 0) {
                            canistergeekLogger.logMessage(
                                "\nfunc_name: batchVerifyTx" #
                                "\nrefund:" #debug_show (refund) # "\n\n"
                            );
                            addICPRefundSettlement(from, refund, memo, Types.icpToken);
                        };
                    };
                    case _ {return #err(#TxNotFound);};
               };
            };
            case _{return #err(#TxNotFound);};
        };
        switch (error) {
            case (?err) {
                return #err(err);
            };
            case _ {};
        };
        var tradeAmount : Nat64 = 0;
        for ((user, amount) in icpSettlments.entries()) {
            addICPSettlement(user, amount, memo, Types.icpToken);
            tradeAmount += amount;
        };
        return #ok(tokenIdentifiers.toArray());
    };

    //check icp transfer and order
    //ICP transfer from buyer to Shiku,
    //NFT transfer is successful and then ICP will be transferred to the seller,
    //NFT transfer fails and ICP will be rpeturned to the buyer
    public shared (msg) func verifyTxWithMemo(height : Nat64, token : TokenSpec) : async VerifyResult {
        let transaction = await LedgerInterface.query_blocks(token.canister,height);
        switch(transaction){
            case (?tx){
               switch (tx.operation) {
                    case (? #Transfer(transfer)) {
                        let from = AIDHex.encode(transfer.from);
                        let transferTo = AIDHex.encode(transfer.to);
                        canistergeekLogger.logMessage(
                            "\nfunc_name: verifyTxWithMemo" #
                            "\nto:" # debug_show (transferTo) #
                            "\nfrom:" # debug_show (from) # "\n\n"
                        );
                        switch (trade.getTradeInfoByTid(Nat64.toNat(tx.memo))) {
                            case (?listing) {
                                switch (listing) {
                                    case (#dutchAuction(dutchAuction)) {
                                        if(dutchAuction.token.canister != token.canister){
                                            return #err(#Rejected); 
                                        };
                                        let tokenIdentifier = dutchAuction.tokenIdentifier;
                                        let toAID = AviateAID.toText(AviateAID.fromPrincipal(Principal.fromActor(this), null));
                                        if (Hex.equal(transferTo, toAID)) {
                                            return #err(#Unauthorized(transferTo));
                                        };

                                        if (Time.now() < dutchAuction.startTime) {
                                            addICPRefundSettlement(from, transfer.amount.e8s, tx.memo, dutchAuction.token);
                                            return #err(#Other("auction has not started"));
                                        };
                                        if (Time.now() > dutchAuction.endTime) {
                                            addICPRefundSettlement(from, transfer.amount.e8s, tx.memo, dutchAuction.token);
                                            return #err(#Other("auction time has expired"));
                                        };

                                        let diffTime = Nat64.fromNat(Int.abs(Time.now() - dutchAuction.startTime));
                                        let reduceNum = Nat64.div(diffTime, dutchAuction.reduceTime);
                                        let reducePrice = Nat64.mul(reduceNum, dutchAuction.reducePrice);
                                        var currPrice : Nat64 = 0;

                                        if (reducePrice >= dutchAuction.startPrice) {
                                            currPrice := dutchAuction.floorPrice;
                                        } else {
                                            currPrice := dutchAuction.startPrice - reducePrice;
                                        };
                                        if (currPrice <= dutchAuction.floorPrice) {
                                            currPrice := dutchAuction.floorPrice;
                                        };
                                        canistergeekLogger.logMessage(
                                            "\nfunc_name: verifyTx" #
                                            "\nreduceNum:" # debug_show (reduceNum) #
                                            "\nreducePrice:" # debug_show (reducePrice) #
                                            "\ncurrPrice:" # debug_show (currPrice) #
                                            "\nheight: " # debug_show (height) # "\n\n"
                                        );

                                        if (currPrice == transfer.amount.e8s) {
                                            var to : User = #address(from);
                                            let collection = Types.TokenIdentifier.getCollectionId(tokenIdentifier);
                                            let erc721 : Collection = actor(collection);
                                            let transferResponse = await erc721.transfer({
                                                from = #principal(dutchAuction.seller);
                                                to = to;
                                                token = tokenIdentifier;
                                                amount = 1;
                                                memo = Blob.fromArray([]);
                                                notify = false;
                                                subaccount = null;
                                            });
                                            switch (transferResponse) {
                                                case (#ok(ok)) {
                                                    let royality = _getRoyalities(Principal.fromText(collection));
                                                    let royalties = Nat64.div(currPrice * royality.rate, Nat64.pow(10,royality.precision));
                                                    let platformFees = Nat64.div(currPrice * 3, Nat64.pow(10, 2));
                                                    var amount = currPrice - royalties - platformFees;
                                                    let creator = await _getCreator(Principal.fromText(collection));
                                                    //payment
                                                    addICPSettlement(dutchAuction.payee, amount, tx.memo, dutchAuction.token);
                                                    addICPSettlement(#principal(platformFee.account), platformFees, tx.memo, dutchAuction.token);
                                                    addICPSettlement(creator, royalties, tx.memo, dutchAuction.token);

                                                    var to : ?Principal = null;
                                                    if (Types.AccountIdentifier.fromPrincipal(msg.caller, null) == from) {
                                                        to := ?msg.caller;
                                                    };
                                                    #ok(tokenIdentifier);
                                                };
                                                case (#err(err)) {
                                                    addICPRefundSettlement(from, transfer.amount.e8s, tx.memo, dutchAuction.token);
                                                    #err(err);
                                                };
                                            };
                                        } else {
                                            addICPRefundSettlement(from, transfer.amount.e8s, tx.memo, dutchAuction.token);
                                            return #err(#VerifyTxErr);
                                        };
                                    };
                                    case (#fixed(fixed)) {
                                        if(fixed.token.canister != token.canister){
                                            return #err(#Rejected); 
                                        };
                                        let tokenIdentifier = fixed.tokenIdentifier;
                                        let toAID = AviateAID.toText(AviateAID.fromPrincipal(Principal.fromActor(this), null));
                                        if (not Hex.equal(transferTo, toAID)) {
                                            return #err(#Unauthorized(transferTo));
                                        };
                                        if (fixed.price == transfer.amount.e8s) {
                                            var to : User = #address(from);
                                            if (Types.TokenIdentifier.isPrincipal(tokenIdentifier, Principal.fromText("ecujo-liaaa-aaaam-aafja-cai")) or Types.TokenIdentifier.isPrincipal(tokenIdentifier, Principal.fromText("ft6xr-taaaa-aaaam-aafmq-cai")) or Types.TokenIdentifier.isPrincipal(tokenIdentifier, Principal.fromText("bjcsj-rqaaa-aaaah-qcxqq-cai")) or Types.TokenIdentifier.isPrincipal(tokenIdentifier, Principal.fromText("ml2cx-yqaaa-aaaah-qc2xq-cai")) or Types.TokenIdentifier.isPrincipal(tokenIdentifier, Principal.fromText("o7ehd-5qaaa-aaaah-qc2zq-cai")) or Types.TokenIdentifier.isPrincipal(tokenIdentifier, Principal.fromText("nusra-3iaaa-aaaah-qc2ta-cai"))) {
                                                if (from == Types.AccountIdentifier.fromPrincipal(msg.caller, null)) {
                                                    to := #principal(msg.caller);
                                                } else {
                                                    return #err(#Other("verify must be called by itself"));
                                                };
                                            };
                                            let collection = Types.TokenIdentifier.getCollectionId(tokenIdentifier);
                                            let erc721 : Collection = actor(collection);
                                            let transferResponse = await erc721.transfer({
                                                from = #principal(fixed.seller);
                                                to = to;
                                                token = tokenIdentifier;
                                                amount = 1;
                                                memo = Blob.fromArray([]);
                                                notify = false;
                                                subaccount = null;
                                            });
                                            switch (transferResponse) {
                                                case (#ok(ok)) {
                                                    let royality = _getRoyalities(Principal.fromText(collection));
                                                    let royalties = Nat64.div(fixed.price * royality.rate, Nat64.pow(10,royality.precision));
                                                    let platformFees = Nat64.div(fixed.price * platformFee.fee, 100);
                                                    let amount = fixed.price - royalties - platformFees;
                                                    let creator = await _getCreator(Principal.fromText(collection));
                                                    addICPSettlement(#principal(fixed.seller), amount, tx.memo, fixed.token);
                                                    addICPSettlement(#principal(platformFee.account), platformFees, tx.memo, fixed.token);
                                                    addICPSettlement(creator, royalties, tx.memo, fixed.token);
                                                    var to : ?Principal = null;
                                                    if (Types.AccountIdentifier.fromPrincipal(msg.caller, null) == from) {
                                                        to := ?msg.caller;
                                                    };

                                                    #ok(tokenIdentifier);
                                                };
                                                case (#err(err)) {
                                                    addICPRefundSettlement(from, transfer.amount.e8s, tx.memo, fixed.token);
                                                    #err(err);
                                                };
                                            };
                                        } else {
                                            addICPRefundSettlement(from, transfer.amount.e8s, tx.memo, fixed.token);
                                            return #err(#VerifyTxErr);
                                        };
                                    };
                                    case _ return #err(#NotSell);
                                };
                            };
                            case (_) {
                                let toAID = AviateAID.toText(AviateAID.fromPrincipal(Principal.fromActor(this), null));
                                if (Hex.equal(transferTo, toAID)) {
                                    return #err(#Unauthorized(transferTo));
                                };
                                addICPRefundSettlement(from, transfer.amount.e8s, tx.memo, token);
                                return #err(#NotList);
                            };
                        };
                    };
                    case _ {
                        return #err(#TxNotFound);
                    };
                }; 
            };
            case _ {
                return #err(#TxNotFound);
            };
        }
    };

    private func _sendICP(to : Principal, amount : Price, memo : Nat64, from_subaccount : ?Blob, token : TokenSpec) : async Bool {
        if (amount == 0) {
            return true;
        };
        let ledgerActor : Ledger.Self = actor (token.canister);
        let res = await ledgerActor.transfer({
            memo = memo;
            from_subaccount = from_subaccount;
            to = AviateAID.fromPrincipal(to, null);
            amount = { e8s = amount - token.fee };
            fee = { e8s = token.fee };
            created_at_time = ?{
                timestamp_nanos = Nat64.fromNat(Int.abs(Time.now()));
            };
        });
        transferIndex += 1;
        switch (res) {
            case (#Ok(_)) {
                return true;
            };
            case (#Err(err)) {
                canistergeekLogger.logMessage(
                    "\nfunc_name: _sendICP" #
                    "\nerr:" #debug_show (err) # "\n\n"
                );
                return false;
            };
        };
    };

    private func checkOwner(tokenIdentifier : TokenIdentifier, seller : User) : async Bool {
        let erc721 : Collection = actor(Types.TokenIdentifier.getCollectionId(tokenIdentifier));
        let result = await erc721.bearer(tokenIdentifier);
        switch (result) {
            case (#ok(accountIdentifier)) {
                switch (seller) {
                    case (#principal(pid)) {
                        return accountIdentifier == Types.AccountIdentifier.fromPrincipal(pid, null);
                    };
                    case (#address(aid)) {
                        return accountIdentifier == aid;
                    };
                };
            };
            case _ {
                return false;
            };
        };
    };

    private func checkAllowance(
        allowance : {
            owner : User;
            spender : Principal;
            token : TokenIdentifier;
        }
    ) : async Bool {
        let erc721 : Collection = actor(Types.TokenIdentifier.getCollectionId(allowance.token));
        let result = await erc721.allowance(allowance);
        switch (result) {
            case (#ok(balance)) {
                return balance == 1;
            };
            case _ {
                return false;
            };
        };
    };
    
    public shared (msg) func makeOffer(newOffer : Trade.NewOffer) : async Trade.OfferResult {
        if (newOffer.bidder != msg.caller) {
            return #err(#other(newOffer.tokenIdentifier, "offer bidder error!"));
        };

        let isOwner : Bool = await checkOwner(newOffer.tokenIdentifier, newOffer.seller);
        if (not isOwner) {
            return #err(#other(newOffer.tokenIdentifier, "offer seller error!"));
        };

        let collectionId = Principal.fromText(Types.TokenIdentifier.getCollectionId(newOffer.tokenIdentifier));
        let collectionInfo = switch (_collections.get(collectionId)) {
            case (?info) {
                info;
            };
            case _ {
                return #err(#other(newOffer.tokenIdentifier, "Collection Not Found!"));
            };
        };
        switch (collectionInfo.releaseTime) {
            case (?releaseTime) {
                if (releaseTime > Time.now()) {
                    return #err(#other(newOffer.tokenIdentifier, "Collection still not release!"));
                };
            };
            case _ {};
        };

        if (newOffer.ttl < Time.now()) {
            return #err(#other(newOffer.tokenIdentifier, "Expired time is not legal!"));
        };
        // check balance
        let subaccount = Utils.principalToSubAccount(msg.caller);
        let subAccountId = AviateAID.toText(AviateAID.fromPrincipal(Principal.fromActor(this), ?subaccount));

        let balance = await checkSubAccountBalance(subAccountId, newOffer.token);
        if (balance < newOffer.price) {
            return #err(#other(newOffer.tokenIdentifier, "Insufficient balance!"));
        };
        let offers = await findOfferByNft(newOffer.tokenIdentifier);

        label inner for (offer in offers.vals()) {
            if (offer.status != #ineffect) {
                continue inner;
            };
            if (offer.bidder == msg.caller) {
                let listResult = await _updateOffer(offer.offerId, newOffer.price);
                switch (listResult) {
                    case (#ok(offerId)) {
                        var toPid : ?Principal = null;
                        var toAid : ?AccountIdentifier = null;
                        switch (newOffer.seller) {
                            case (#principal(pid)) {
                                toAid := ?Types.AccountIdentifier.fromPrincipal(pid, null);
                                toPid := ?pid;
                            };
                            case (#address(aid)) {
                                toAid := ?aid;
                            };
                        };
                    };
                    case _ {};
                };
                return listResult;
            };
        };

        let listResult = trade.makeOffer(newOffer);
        switch (listResult) {
            case (#ok(offerId)) {
                var toPid : ?Principal = null;
                var toAid : ?AccountIdentifier = null;
                switch (newOffer.seller) {
                    case (#principal(pid)) {
                        toAid := ?Types.AccountIdentifier.fromPrincipal(pid, null);
                        toPid := ?pid;
                    };
                    case (#address(aid)) {
                        toAid := ?aid;
                    };
                };
                let tokenObj = Ext.TokenIdentifier.decode(newOffer.tokenIdentifier);
            };
            case _ {};
        };
        listResult;
    };

    private stable var subAccountTradeIndex : Nat64 = 1;

    public shared (msg) func acceptOffer(offerId : Types.OfferId) : async Result.Result<Ledger.BlockIndex, Text> {
        let offer = switch (trade.acceptOffer(offerId, #principal(msg.caller))) {
            case (#err(err)) {
                return #err(err);
            };
            case (#ok(offer)) {
                offer;
            };
        };
        let isOwner : Bool = await checkOwner(offer.tokenIdentifier, offer.seller);
        if (not isOwner) {
            _cancelOffer(offerId, offer);
            return #err("offer seller error!");
        };
        let payee = switch (trade.getTradeInfo(offer.tokenIdentifier)) {
            case (?(#dutchAuction(dutchAuction))) {
                if (dutchAuction.startTime > Time.now()) {
                    return #err("Auction haven't start");
                };
                dutchAuction.payee;
            };
            case _ {
                offer.seller;
            };
        };

        let subaccount = Utils.principalToSubAccount(offer.bidder);
        canistergeekLogger.logMessage(
            "\nfunc_name: acceptOffer" #
            "\noffer_bidder:" # debug_show (Principal.toText(offer.bidder)) # "\n\n"
        );
        let collectionId = Principal.fromText(Types.TokenIdentifier.getCollectionId(offer.tokenIdentifier));
        let collectionInfo = switch (_collections.get(collectionId)) {
            case (?info) {
                info;
            };
            case _ {
                _cancelOffer(offerId, offer);
                return #err("Collection Not Found!");
            };
        };
        switch (collectionInfo.releaseTime) {
            case (?releaseTime) {
                if (releaseTime > Time.now()) {
                    _cancelOffer(offerId, offer);
                    return #err("Collection still not release!");
                };
            };
            case _ {};
        };

        let currentSubAccountTradeIndex = subAccountTradeIndex;
        let platformReceivePrice = offer.price - offer.token.fee;
        let ledgerActor : Ledger.Self = actor (offer.token.canister);
        let res = await ledgerActor.transfer({
            memo = currentSubAccountTradeIndex;
            from_subaccount = ?Blob.fromArray(subaccount);
            to = AviateAID.fromPrincipal(Principal.fromActor(this), null);
            amount = { e8s = platformReceivePrice };
            fee = { e8s = offer.token.fee };
            created_at_time = ?{
                timestamp_nanos = Nat64.fromNat(Int.abs(Time.now()));
            };
        });
        let tokenObj = Ext.TokenIdentifier.decode(offer.tokenIdentifier);
        switch (res) {
            case (#Ok(height)) {
                subAccountTradeIndex += 1;
                let erc721 : Collection = actor(tokenObj.canister);
                let transferResponse = await erc721.transfer({
                    from = offer.seller;
                    to = #principal(offer.bidder);
                    token = offer.tokenIdentifier;
                    amount = 1;
                    memo = Blob.fromArray([]);
                    notify = false;
                    subaccount = null;
                });

                switch (transferResponse) {
                    case (#ok(ok)) {
                        let royality = _getRoyalities(collectionId);
                        let royalties = Nat64.div(platformReceivePrice * royality.rate, Nat64.pow(10,royality.precision));
                        let platformFees = Nat64.div(platformReceivePrice * 3, Nat64.pow(10, 2));
                        let amount = platformReceivePrice - royalties - platformFees;

                        var fromPid : ?Principal = null;
                        var fromAid : ?AccountIdentifier = null;
                        switch (offer.seller) {
                            case (#principal(pid)) {
                                fromAid := ?Types.AccountIdentifier.fromPrincipal(pid, null);
                                fromPid := ?pid;
                            };
                            case (#address(aid)) {
                                fromAid := ?aid;
                            };
                        };
                        let creater = await _getCreator(Principal.fromText(tokenObj.canister));
                        addICPSettlement(payee, amount, currentSubAccountTradeIndex, offer.token);
                        addICPSettlement(#principal(platformFee.account), platformFees, currentSubAccountTradeIndex, offer.token);
                        addICPSettlement(creater, royalties, currentSubAccountTradeIndex, offer.token);
                        return #ok(height);
                    };
                    case (#err(err)) {
                        _cancelOffer(offerId, offer);
                        let subaccount = Utils.principalToSubAccount(offer.bidder);
                        let toAID = AviateAID.toText(AviateAID.fromPrincipal(Principal.fromActor(this), ?subaccount));
                        addICPRefundSettlement(toAID, platformReceivePrice, currentSubAccountTradeIndex, offer.token);
                        return #err("transfer nft error");
                    };
                };
            };
            case (#Err(err)) {
                _cancelOffer(offerId, offer);
                return #err("transfer icp error");
            };
        };
    };

    //ok
    public shared (msg) func rejectOffer(offerId : Types.OfferId) : async Result.Result<(), Text> {
        trade.rejectOffer(offerId, #principal(msg.caller));
    };

    public shared (msg) func rejectOfferByUser(offerId : Types.OfferId) : async Result.Result<(), Text> {
        trade.rejectOfferByUser(offerId, #principal(msg.caller));
    };

    public query (msg) func findOfferByNft(tokenIdentifier : TokenIdentifier) : async [Trade.Offer] {
        trade.findOfferByNft(tokenIdentifier);
    };

    public shared (msg) func findOfferById(offerId : Types.OfferId) : async ?Trade.Offer {
        trade.findOfferById(offerId);
    };
    private func _updateOffer(offerId : Types.OfferId, price : Price) : async Trade.OfferResult {
        let _offer = trade.findOfferById(offerId);
        let offer = Utils.unwrap(_offer);

        let isOwner : Bool = await checkOwner(offer.tokenIdentifier, offer.seller);
        if (not isOwner) {
            return #err(#other(offer.tokenIdentifier, "offer seller error!"));
        };

        //  TODO 判断time
        if (offer.ttl < Time.now()) {
            return #err(#other(offer.tokenIdentifier, "Expired time is not legal!"));
        };
        // check balance
        let subaccount = Utils.principalToSubAccount(offer.bidder);
        let subAccountId = AviateAID.toText(AviateAID.fromPrincipal(Principal.fromActor(this), ?subaccount));
        let balance = await checkSubAccountBalance(subAccountId, offer.token);
        if (balance < price) {
            return #err(#other(offer.tokenIdentifier, "Insufficient balance!"));
        };

        if (not trade.updateOffer(offerId, price, offer.bidder)) {
            return #err(#other(offer.tokenIdentifier, "update offer error!"));
        };
        return #ok(offer.offerId);
    };

    public shared (msg) func updateOffer(offerId : Types.OfferId, price : Price) : async Trade.OfferResult {
        let _offer = trade.findOfferById(offerId);
        let offer = Utils.unwrap(_offer);
        if (offer.bidder != msg.caller) {
            return #err(#other(offer.tokenIdentifier, "offer bidder error!"));
        };
        await _updateOffer(offerId, price);
    };

    public shared (msg) func cancelOffer(offerId : Types.OfferId) : async Bool {
        let _offer = trade.findOfferById(offerId);
        let offer = Utils.unwrap(_offer);
        assert (offer.bidder == msg.caller);
        _cancelOffer(offerId, offer);
        return true;
    };

    private func _cancelOffer(offerId : Types.OfferId, offer : Trade.NewOffer) {
        trade.cancelOffer(offerId);
    };

    public query func getOfferTids() : async [TokenIdentifier] {
        return trade.getOfferTids();
    };

    public shared (msg) func checkOffer(tids : [TokenIdentifier]) : async () {
        for (tid in tids.vals()) {
            let offerList = trade.findOfferByNft(tid);
            label inner for (offer in offerList.vals()) {
                if (Time.now() >= offer.ttl) {
                    trade.expiredOffer(offer.offerId);
                    continue inner;
                };

                let subaccount = Utils.principalToSubAccount(offer.bidder);
                let subAccountId = AviateAID.toText(AviateAID.fromPrincipal(Principal.fromActor(this), ?subaccount));
                let balance = await checkSubAccountBalance(subAccountId, offer.token);
                if (balance < offer.price) {
                    let response = (trade.rejectOffer(offer.offerId, offer.seller));
                    continue inner;
                };
            };
        };
    };

    public shared (msg) func findHighOfferByNft(tid : TokenIdentifier) : async (?Trade.Offer) {
        let highOffer = trade.findHighOfferByNft(tid);
        return highOffer;
    };
    public shared (msg) func dealOffer(tids : [TokenIdentifier]) : async () {
        label inner for (tid in tids.vals()) {
            let highOffer = trade.findHighOfferByNft(tid);
            switch (highOffer) {
                case (?offer) {
                    if (offer.status != #ineffect) {
                        continue inner;
                    };
                    let isOwner : Bool = await checkOwner(offer.tokenIdentifier, offer.seller);
                    if (not isOwner) {
                        _cancelOffer(offer.offerId, offer);
                        continue inner;
                    };
                    if (Time.now() >= offer.ttl) {
                        trade.expiredOffer(offer.offerId);
                        continue inner;
                    };

                    let subaccount = Utils.principalToSubAccount(offer.bidder);
                    let subAccountId1 = AviateAID.toText(AviateAID.fromPrincipal(Principal.fromActor(this), ?subaccount));

                    try {
                        let balance = await checkSubAccountBalance(subAccountId1, offer.token);
                        if (balance < offer.price) {
                            //_cancelOffer(offer.offerId,offer);
                            let response = (trade.rejectOffer(offer.offerId, offer.seller));
                            continue inner;
                        };

                    } catch (e) {
                        continue inner;
                    };

                    switch (trade.getTradeInfo(tid)) {
                        case (?(#dutchAuction(dutchAuction))) {
                            // todo reset ?
                            if (Time.now() < dutchAuction.startTime) {
                                // _cancelOffer(offer.offerId,offer);
                                continue inner;
                            };
                            if (Time.now() > dutchAuction.endTime) {
                                _cancelOffer(offer.offerId, offer);
                                continue inner;
                            };

                            let diffTime = Nat64.fromNat(Int.abs(Time.now() - dutchAuction.startTime));
                            let reduceNum = Nat64.div(diffTime, dutchAuction.reduceTime);
                            let reducePrice = Nat64.mul(reduceNum, dutchAuction.reducePrice);
                            var currPrice : Nat64 = 0;
                            if (reducePrice >= dutchAuction.startPrice) {
                                currPrice := dutchAuction.floorPrice;
                            } else {
                                currPrice := dutchAuction.startPrice - reducePrice;
                            };
                            if (currPrice <= dutchAuction.floorPrice) {
                                currPrice := dutchAuction.floorPrice;
                            };

                            if (offer.price >= currPrice) {

                                switch (trade.acceptOffer(offer.offerId, offer.seller)) {
                                    case (#err(err)) {
                                        _cancelOffer(offer.offerId, offer);
                                        continue inner;
                                    };
                                    case (#ok(offer)) {
                                        let allOffersByTid = trade.findOfferByNft(tid);
                                        label innerid for (offerByTid in allOffersByTid.vals()) {
                                            if (offerByTid.offerId != offer.offerId) {
                                                if (offerByTid.status != #ineffect) {
                                                    continue innerid;
                                                };

                                                switch (trade.rejectOffer(offerByTid.offerId, offerByTid.seller)) {
                                                    case (#err(err)) {
                                                        continue inner;
                                                    };

                                                    case (#ok(offer)) {};
                                                };
                                            };
                                        };
                                    };
                                };

                                let currentSubAccountTradeIndex = subAccountTradeIndex;
                                let platformReceivePrice = offer.price - offer.token.fee;
                                let ledgerActor : Ledger.Self = actor (offer.token.canister);
                                let res = await ledgerActor.transfer({
                                    memo = currentSubAccountTradeIndex;
                                    from_subaccount = ?Blob.fromArray(subaccount);
                                    to = AviateAID.fromPrincipal(Principal.fromActor(this), null);
                                    amount = { e8s = platformReceivePrice };
                                    fee = { e8s = offer.token.fee };
                                    created_at_time = ?{
                                        timestamp_nanos = Nat64.fromNat(Int.abs(Time.now()));
                                    };
                                });
                                subAccountTradeIndex += 1;

                                switch (res) {
                                    case (#Ok(height)) {
                                        let tokenObj = Ext.TokenIdentifier.decode(tid);
                                        let erc721 : Collection = actor(tokenObj.canister);
                                        let transferResponse = await erc721.transfer({
                                            from = offer.seller;
                                            to = #principal(offer.bidder);
                                            token = tid;
                                            amount = 1;
                                            memo = Blob.fromArray([]);
                                            notify = false;
                                            subaccount = null;
                                        });
                                        switch (transferResponse) {
                                            case (#ok(ok)) {
                                                let royality = _getRoyalities(Principal.fromText(tokenObj.canister));
                                                let royalties = Nat64.div(platformReceivePrice * royality.rate, Nat64.pow(10,royality.precision));
                                                let platformFees = Nat64.div(platformReceivePrice * 3, Nat64.pow(10, 2));
                                                let share_amount = Nat64.div(currPrice * 10, Nat64.pow(10, 2));
                                                var amount = platformReceivePrice - royalties - platformFees - share_amount;
                                                let creator = await _getCreator(Principal.fromText(tokenObj.canister));
                                                addICPSettlement(dutchAuction.payee, amount, currentSubAccountTradeIndex, dutchAuction.token);
                                                addICPSettlement(#principal(platformFee.account), platformFees, currentSubAccountTradeIndex, dutchAuction.token);
                                                addICPSettlement(creator, royalties, currentSubAccountTradeIndex, dutchAuction.token);
                                            };
                                            case (#err(err)) {
                                                _cancelOffer(offer.offerId, offer);
                                                addICPRefundSettlement(subAccountId1, platformReceivePrice, currentSubAccountTradeIndex, offer.token);
                                                continue inner;
                                            };
                                        };
                                    };
                                    case (#Err(err)) {
                                        _cancelOffer(offer.offerId, offer);
                                        continue inner;
                                    };
                                };
                            };

                        };
                        case _ {};
                    };
                };
                case _ {

                };
            };
        };
    };

    // account_balance_dfx
    public func checkSubAccountBalance(accountid : AccountIdentifier, token : TokenSpec) : async Nat64 {
        try {
            let ledgerActor : Ledger.Self = actor (token.canister);
            let res = await ledgerActor.account_balance({
                account = Blob.fromArray(AIDHex.decode(accountid));
            });
            return res.e8s;
        } catch (e) {
            canistergeekLogger.logMessage(
                "\nfunc_name: checkSubAccountBalance" #
                "\ntryerror:" # debug_show (Error.message(e)) # "\n\n"
            );
            P.unreachable();
        };

    };

    // canistergeekLogger
    stable var _canistergeekLoggerUD : ?Canistergeek.LoggerUpgradeData = null;
    private let canistergeekLogger = Canistergeek.Logger();

    public query ({ caller }) func getCanisterLog(request : ?Canistergeek.CanisterLogRequest) : async ?Canistergeek.CanisterLogResponse {
        assert (Utils.existIm<Principal>(creator_whitelist, func(v) { v == caller }));
        return canistergeekLogger.getLog(request);
    };
    ///stable
    system func preupgrade() {
        _collectionArray := Iter.toArray(_collections.entries());
        _icpSettlements_entries := Iter.toArray(_icpSettlements.entries());
        _icpRefundSettlements_entries := Iter.toArray(_icpRefundSettlements.entries());
        _canistergeekLoggerUD := ?canistergeekLogger.preupgrade();
        _cartsState := Iter.toArray(_carts.entries());
    };

    system func postupgrade() {
        _collectionArray := [];
        _icpSettlements_entries := [];
        _icpRefundSettlements_entries := [];
        canistergeekLogger.postupgrade(_canistergeekLoggerUD);
        _canistergeekLoggerUD := null;
        canistergeekLogger.setMaxMessagesCount(5000);
        canistergeekLogger.logMessage("postupgrade");
        _cartsState := [];
    };

    type ICPSale = Types.ICPSale;
    type SettleICPResult = Types.SettleICPResult;
    private stable var _icpSaleIndex : Nat = 1;
    private stable var _icpSettlements_entries : [(Nat, ICPSale)] = [];
    private var _icpSettlements : TrieMap.TrieMap<Nat, ICPSale> = TrieMap.fromEntries(_icpSettlements_entries.vals(), Nat.equal, Hash.hash);

    public query func getICPSettlements() : async [(Nat, ICPSale)] {
        Iter.toArray(_icpSettlements.entries());
    };

    public shared (msg) func batchSettleICP(indexs : [Nat]) : async [SettleICPResult] {
        var num : Nat = 0;
        let result = Buffer.Buffer<SettleICPResult>(0);
        label c for (index in indexs.vals()) {
            if (num > 5) {
                return result.toArray();
            };
            switch (_icpSettlements.get(index)) {
                case (?settlement) {
                    // process
                    if (settlement.retry >= 3) {
                        result.add(#err(#RetryExceed));
                        continue c;
                    };
                    num := num + 1;
                    _icpSettlements.delete(index);
                    try {
                        var resp : Bool = false;
                        switch (settlement.user) {
                            case (#principal(pid)) {
                                resp := await _sendICP(pid, settlement.price, settlement.memo, null, settlement.token);
                            };
                            case (#address(aid)) {
                                resp := await _sendICPToUser(aid, settlement.price, settlement.memo, null, settlement.token);
                            };
                        };
                        if (not resp) {
                            // retry
                            _icpSettlements.put(
                                index,
                                {
                                    user = settlement.user;
                                    price = settlement.price;
                                    retry = settlement.retry + 1;
                                    memo = settlement.memo;
                                    token = settlement.token;
                                },
                            );
                            result.add(#err(#SettleErr));
                        } else {
                            result.add(#ok());
                        };
                    } catch (e) {
                        Debug.print(debug_show ("try cath error: "));
                        _icpSettlements.put(
                            index,
                            {
                                user = settlement.user;
                                price = settlement.price;
                                retry = settlement.retry + 1;
                                memo = settlement.memo;
                                token = settlement.token;
                            },
                        );
                        result.add(#err(#SettleErr));
                    };
                };
                case (_) result.add(#err(#NoSettleICP));
            };
        };
        result.toArray();
    };

    private func addICPSettlement(_user : User, _price : Nat64, memo : Nat64, token : TokenSpec) {
        _icpSettlements.put(
            _icpSaleIndex,
            {
                user = _user;
                price = _price;
                retry = 0;
                memo = memo;
                token = token;
            },
        );
        _icpSaleIndex += 1;
    };

    //icp refund
    private stable var _icpRefundIndex : Nat = 1;
    type ICPRefund = Types.ICPRefund;
    private stable var _icpRefundSettlements_entries : [(Nat, ICPRefund)] = [];
    private var _icpRefundSettlements : TrieMap.TrieMap<Nat, ICPRefund> = TrieMap.fromEntries(_icpRefundSettlements_entries.vals(), Nat.equal, Hash.hash);

    public query func getICPRefundSettlements() : async [(Nat, ICPRefund)] {
        Iter.toArray(_icpRefundSettlements.entries());
    };

    public shared (msg) func batchSettleICPRefund(indexs : [Nat]) : async () {
        var num : Nat = 0;
        label c for (index in indexs.vals()) {
            if (num > 5) {
                return;
            };
            switch (_icpRefundSettlements.get(index)) {
                case (?settlement) {
                    // process
                    if (settlement.retry >= 3) {
                        continue c;
                    };
                    num := num + 1;
                    _icpRefundSettlements.delete(index);
                    try {
                        let resp = await _sendICPToUser(settlement.user, settlement.price, settlement.memo, null, settlement.token);
                        if (not resp) {
                            _icpRefundSettlements.put(
                                index,
                                {
                                    user = settlement.user;
                                    price = settlement.price;
                                    retry = settlement.retry + 1;
                                    memo = settlement.memo;
                                    token = settlement.token;
                                },
                            );
                        };
                    } catch (e) {
                        Debug.print(debug_show ("try cath error: "));
                        _icpRefundSettlements.put(
                            index,
                            {
                                user = settlement.user;
                                price = settlement.price;
                                retry = settlement.retry + 1;
                                memo = settlement.memo;
                                token = settlement.token;
                            },
                        );
                    };
                };
                case (_) {};
            };
        };
    };

    private func addICPRefundSettlement(_user : AccountIdentifier, _price : Nat64, memo : Nat64, token : TokenSpec) {
        _icpRefundSettlements.put(
            _icpRefundIndex,
            {
                user = _user;
                price = _price;
                retry = 0;
                memo = memo;
                token = token;
            },
        );
        _icpRefundIndex += 1;
    };

    public func balance() : async Nat {
        return Cycles.balance();
    };

    public func wallet_receive() : async Nat {
        Cycles.accept(Cycles.available());
    };

    type TransferError = {
        #BadFee : { expected_fee : Ledger.ICP };
        #InsufficientFunds : { balance : Ledger.ICP };
        #TxTooOld : { allowed_window_nanos : Nat64 };
        #TxCreatedInFuture;
        #TxDuplicate : { duplicate_of : Ledger.BlockIndex };
        #Other : Text;
    };
    type TransferResult = Result.Result<Ledger.BlockIndex, TransferError>;
    private func _sendICPToUser(to : AccountIdentifier, amount : Price, memo : Nat64, from_subaccount : ?Blob, token : TokenSpec) : async Bool {
        let ledgerActor : Ledger.Self = actor (token.canister);
        let res = await ledgerActor.transfer({
            memo = memo;
            from_subaccount = from_subaccount;
            to = Blob.fromArray(AIDHex.decode(to));
            amount = { e8s = amount - token.fee };
            fee = { e8s = token.fee };
            created_at_time = ?{
                timestamp_nanos = Nat64.fromNat(Int.abs(Time.now()));
            };
        });
        switch (res) {
            case (#Ok(height)) {
                return true;
            };
            case (#Err(err)) {
                canistergeekLogger.logMessage(
                    "\nfunc_name: _sendICPToUser" #
                    "\nerr:" #debug_show (err) # "\n\n"
                );
                return false;
            };
        };
    };

    public shared (msg) func getPayAddress() : async Text {
        if (Principal.equal(Principal.fromText("2vxsx-fae"), msg.caller)) {
            return "";
        };
        let subaccount = Utils.principalToSubAccount(msg.caller);
        let toAID = AviateAID.toText(AviateAID.fromPrincipal(Principal.fromActor(this), ?subaccount));
        return toAID;
    };

    public query (msg) func getPayAddressWho(principal : Principal) : async Text {
        let subaccount = Utils.principalToSubAccount(principal);
        let toAID = AviateAID.toText(AviateAID.fromPrincipal(Principal.fromActor(this), ?subaccount));
        return toAID;
    };

    // withdraw subaccount 提取子账号的钱
    // public shared(msg) func withdrawBySubAccount(to : AccountIdentifier,amount : Price) : async Bool {
    public shared (msg) func withdrawBySubAccount(to : User, amount : Price, token : TokenSpec) : async Bool {

        if (Principal.equal(Principal.fromText("2vxsx-fae"), msg.caller)) {
            return false;
        };
        let subaccount = Utils.principalToSubAccount(msg.caller);
        switch (to) {
            case (#principal(pid)) {
                return await _sendICP(pid, amount, 0, ?Blob.fromArray(subaccount), token);
            };
            case (#address(aid)) {
                return await _sendICPToUser(aid, amount, 0, ?Blob.fromArray(subaccount), token);
            };
        };
    };


    public shared (msg) func flushICPSettlement() : async () {
        assert (msg.caller == _owner);
        _icpSettlements := TrieMap.TrieMap<Nat, ICPSale>(Nat.equal, Hash.hash);
    };

    public shared (msg) func flushICPRefundSettlement() : async () {
        assert (msg.caller == _owner);
        _icpRefundSettlements := TrieMap.TrieMap<Nat, ICPRefund>(Nat.equal, Hash.hash);
    };

    //entrepot owner
    private stable var _entrepot_owners_entries : [(Principal, AccountIdentifier)] = [];
    private var _entrepot_creator : TrieMap.TrieMap<Principal, AccountIdentifier> = TrieMap.fromEntries(_entrepot_owners_entries.vals(), Principal.equal, Principal.hash);
    private func _getCreator(canister : Principal): async User{
        switch(_entrepot_creator.get(canister)){
            case (?owner) {
                return #address(owner);
            };
            case _ {
                let erc721 : Collection = actor(Principal.toText(canister));
                let minter = await erc721.getMinter();
                return #principal(minter);
            }
        };
    };

    public shared(msg) func setEntrepotCreator(canister : Principal,address : AccountIdentifier) {
        assert(msg.caller == _owner);
        _entrepot_creator.put(canister,address)
    };

    private func _getRoyalities(canister : Principal) : Types.Royality{
        switch(_collections.get(canister)){
            case (?info) {
                info.royalties;
            };
            case _ {
                P.unreachable();
            };
        }
    };
};
