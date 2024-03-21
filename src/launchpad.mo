import Array "mo:base/Array";
import AviateAID "mo:principal/blob/AccountIdentifier";
import AviatePrincipal "mo:principal/Principal";
import Binary "mo:encoding/Binary";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Canistergeek "mo:canistergeek/canistergeek";
import Debug "mo:base/Debug";
import Hash "mo:base/Hash";
import HashMap "mo:base/HashMap";
import Hex "mo:encoding/Hex";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import Ledger "ledger";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Option "mo:base/Option";
import Principal "mo:base/Principal";
import Random "mo:base/Random";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Time "mo:base/Time";
import TrieMap "mo:base/TrieMap";
import TrieSet "mo:base/TrieSet";
import Types "types";
import Utils "utils";
import AIDHex "mo:crypto/Hex";
import LedgerInterface "ledgerInterface";

shared (install) actor class LaunchPadActor(owner : Principal, platformFeeAccount : Principal) = this {
    type Price = Types.Price;
    type TokenIdentifier = Types.TokenIdentifier;
    type AccountIdentifier = Types.AccountIdentifier;
    type User = Types.User;
    type PlatformFee = {
        var fee : Price;
        var account : Principal;
        var precision : Nat64;
    };

    stable var platformFee : PlatformFee = {
        var fee = 10;
        var account = platformFeeAccount;
        var precision = 2;
    };

    stable var _kyc_switch : Bool = false;
    public shared(msg) func setKycSwitch(open : Bool) : async () {
        assert (msg.caller == _owner);
        _kyc_switch := open;
    };

    private stable var pointRatio : Nat64 = 10;

    public shared (msg) func setPointRatio(newRatio : Nat64) : async () {
        assert (msg.caller == _owner);
        pointRatio := newRatio;
    };

    public query func queryPointRatio() : async Nat64 {
        pointRatio;
    };

    private func _hash(h : Nat64) : Hash.Hash {
        Nat32.fromNat(Nat64.toNat(h));
    };

    type CollectionInfo = Types.LaunchpadCollectionInfo;
    private stable var _index : Nat64 = 0;
    private stable var _collectionArray : [(Principal, CollectionInfo)] = [];
    private var _collections = HashMap.HashMap<Principal, CollectionInfo>(0, Principal.equal, Principal.hash);
    private stable var _registryArray : [(Nat64, Principal)] = [];
    private var _registry = HashMap.HashMap<Nat64, Principal>(0, Nat64.equal, _hash);
    private stable var _collectionRemainingTokenArray : [(Principal, [Nat])] = [];
    private var _collectionRemainingTokens = HashMap.HashMap<Principal, [Nat]>(0, Principal.equal, Principal.hash);

    private stable var _whitelistArray : [(Principal, [(AccountIdentifier, Nat)])] = [];
    private var _whitelist : HashMap.HashMap<Principal, HashMap.HashMap<AccountIdentifier, Nat>> = HashMap.HashMap<Principal, HashMap.HashMap<AccountIdentifier, Nat>>(0, Principal.equal, Principal.hash);
    private stable var _normalBoughtArray : [(Principal, [(AccountIdentifier, Nat)])] = [];
    private var _normalBought : HashMap.HashMap<Principal, HashMap.HashMap<AccountIdentifier, Nat>> = HashMap.HashMap<Principal, HashMap.HashMap<AccountIdentifier, Nat>>(0, Principal.equal, Principal.hash);
    private stable var _claimedArray : [(Principal, [TokenIdentifier])] = [];
    private var _claimed = HashMap.HashMap<Principal, [TokenIdentifier]>(0, Principal.equal, Principal.hash);

    private stable var _owner : Principal = owner;

    public shared (msg) func setOwner(owner : Principal) : async () {
        assert (msg.caller == _owner);
        _owner := owner;
    };

    public shared (msg) func getOwner() : async Principal {
        _owner;
    };

    public shared (msg) func setPlatformAccount(account : Principal) : async () {
        assert (msg.caller == _owner);
        platformFee.account := account;
    };

    public shared (msg) func setPlatformFee(fee : Price, precision : Nat64) : async () {
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

    // canistergeekLogger
    stable var _canistergeekLoggerUD : ?Canistergeek.LoggerUpgradeData = null;
    private let canistergeekLogger = Canistergeek.Logger();

    public query ({ caller }) func getCanisterLog(request : ?Canistergeek.CanisterLogRequest) : async ?Canistergeek.CanisterLogResponse {
        assert (Utils.existIm<Principal>(creator_whitelist, func(v) { v == caller }));
        return canistergeekLogger.getLog(request);
    };

    public shared (msg) func addWhitelist(collection : Principal, users : [AccountIdentifier]) : async () {
        assert (Utils.existIm<Principal>(creator_whitelist, func(v) { v == msg.caller }));
        switch (_whitelist.get(collection)) {
            case (?whitelist) {
                for (user in users.vals()) {
                    if (not Option.isSome(whitelist.get(user))) {
                        whitelist.put(user, 0);
                    };
                };
                _whitelist.put(collection, whitelist);
            };
            case _ {
                var whitelist = HashMap.HashMap<AccountIdentifier, Nat>(users.size(), Text.equal, Text.hash);
                for (user in users.vals()) {
                    whitelist.put(user, 0);
                };
                _whitelist.put(collection, whitelist);
            };
        };
    };

    public shared (msg) func delWhitelist(collection : Principal) : async () {
        assert (Utils.existIm<Principal>(creator_whitelist, func(v) { v == msg.caller }));
        _whitelist.delete(collection);
    };

    public query func listWhitelist(collection : Principal) : async [(AccountIdentifier, Nat)] {
        switch (_whitelist.get(collection)) {
            case (?whitelist) {
                Iter.toArray(whitelist.entries());
            };
            case _ { [] };
        };
    };

    public query func listBought(collection : Principal) : async [(AccountIdentifier, Nat)] {
        switch (_normalBought.get(collection)) {
            case (?bought) {
                Iter.toArray(bought.entries());
            };
            case _ { [] };
        };
    };

    func _addbought(collection : Principal, user : AccountIdentifier, count : Nat) {
        switch (_collections.get(collection)) {
            case (?info) {
                if (Time.now() > info.whitelistTimeStart and Time.now() < info.whitelistTimeEnd) {
                    switch (_whitelist.get(collection)) {
                        case (?whitelist) {
                            switch (whitelist.get(user)) {
                                case (?nat) {
                                    whitelist.put(user, nat + count);
                                };
                                case _ {
                                    whitelist.put(user, count);
                                };
                            };
                            _whitelist.put(collection, whitelist);
                        };
                        case _ {};
                    };
                } else {
                    switch (_normalBought.get(collection)) {
                        case (?normalBought) {
                            switch (normalBought.get(user)) {
                                case (?nat) {
                                    normalBought.put(user, nat + count);
                                };
                                case _ {
                                    normalBought.put(user, count);
                                };
                            };
                            _normalBought.put(collection, normalBought);
                        };
                        case _ {
                            var normalBought = HashMap.HashMap<AccountIdentifier, Nat>(0, Text.equal, Text.hash);
                            normalBought.put(user, count);
                            _normalBought.put(collection, normalBought);
                        };
                    };
                };
            };
            case _ {};
        };
    };

    public query (msg) func isWhitelist(collection : Principal) : async Result.Result<Nat, Text> {
        switch (_whitelist.get(collection)) {
            case (?whitelist) {
                switch (whitelist.get(Types.AccountIdentifier.fromPrincipal(msg.caller, null))) {
                    case (?nat) {
                        return #ok(nat);
                    };
                    case _ {
                        return #err("Not Whitelist");
                    };
                };
            };
            case _ {
                return #err("Not Whitelist");
            };
        };
    };
    private func _isWhitelist(collection : Principal, user : Types.User) : Bool {
        let aid = Types.User.toAID(user);
        switch (_whitelist.get(collection)) {
            case (?whitelist) {
                switch (whitelist.get(aid)) {
                    case (?nat) {
                        let info = Utils.unwrap(_collections.get(collection));
                        if (Time.now() > info.whitelistTimeStart and Time.now() < info.whitelistTimeEnd) {
                            return true;
                        };
                        return false;
                    };
                    case _ {
                        return false;
                    };
                };
            };
            case _ {
                return false;
            };
        };
    };

    public shared (msg) func importCollection(init : CollectionInfo) : async Result.Result<(), Types.CollectionErr> {
        assert (Utils.existIm<Principal>(creator_whitelist, func(v) { v == msg.caller }) or Utils.existIm<Principal>(second_creator_whitelist, func(v) { v == msg.caller }));
        switch (_collections.get(init.id)) {
            case (?info) {
                _collections.put(init.id, _makeCollectionInfo(info.index, init));
            };
            case _ {
                let index = _index;
                let info = _makeCollectionInfo(index, init);
                _collections.put(info.id, info);
                _registry.put(index, info.id);
                _index += 1;
            };
        };
        #ok(());
    };

    public shared (msg) func auditCollection(collectionId : Principal, auditType : Text) : async Bool {
        assert (Utils.existIm<Principal>(creator_whitelist, func(v) { v == msg.caller }));
        switch (_collections.get(collectionId)) {
            case (?info) {
                _collections.put(collectionId, _makeApprovedCollectionInfo(info.index, info, auditType));
                return true;
            };
            case _ {
                return false;
            };
        };
    };

    public shared (msg) func updateCollection(info1 : CollectionInfo) : async Bool {
        assert (Utils.existIm<Principal>(creator_whitelist, func(v) { v == msg.caller }));
        let info = Utils.unwrap(_collections.get(info1.id));
        _collections.put(info.id, _makeCollectionInfo(info.index, info1));
        true;
    };

    public shared (msg) func removeCollection(id : Principal) : async Bool {
        assert (Utils.existIm<Principal>(creator_whitelist, func(v) { v == msg.caller }));
        switch (_collections.remove(id)) {
            case (?info) {
                _registry.delete(info.index);
            };
            case _ {};
        };
        _collectionRemainingTokens.delete(id);
        _whitelist.delete(id);
        true;
    };

    private func _makeCollectionInfo(index : Nat64, info1 : CollectionInfo) : CollectionInfo {
        {
            id = info1.id;
            index = index;
            name = info1.name;
            featured = info1.featured;
            featured_mobile = info1.featured_mobile;
            description = info1.description;
            totalSupply = info1.totalSupply;
            avaliable = info1.avaliable;
            addTime = info1.addTime;
            links = info1.links;
            starTime = info1.starTime;
            endTime = info1.endTime;
            price = info1.price;
            normalCount = info1.normalCount;
            normalPerCount = info1.normalPerCount;
            whitelistPrice = info1.whitelistPrice;
            whitelistTimeStart = info1.whitelistTimeStart;
            whitelistTimeEnd = info1.whitelistTimeEnd;
            whitelistCount = info1.whitelistCount;
            whitelistPerCount = info1.whitelistPerCount;
            approved = info1.approved;
            standard = info1.standard;
            typicalNFTs = info1.typicalNFTs;
            production = info1.production;
            team = info1.team;
            teamImage = info1.teamImage;
            faq = info1.faq;
            banner = info1.banner;
        };
    };

    private func _makeApprovedCollectionInfo(index : Nat64, info1 : CollectionInfo, auditType : Text) : CollectionInfo {
        {
            id = info1.id;
            index = index;
            name = info1.name;
            featured = info1.featured;
            featured_mobile = info1.featured_mobile;
            description = info1.description;
            totalSupply = info1.totalSupply;
            avaliable = info1.avaliable;
            addTime = info1.addTime;
            links = info1.links;
            starTime = info1.starTime;
            endTime = info1.endTime;
            price = info1.price;
            normalCount = info1.normalCount;
            normalPerCount = info1.normalPerCount;
            normalPerCount1 = info1.normalPerCount;
            whitelistPrice = info1.whitelistPrice;
            whitelistTimeStart = info1.whitelistTimeStart;
            whitelistTimeEnd = info1.whitelistTimeEnd;
            whitelistCount = info1.whitelistCount;
            whitelistPerCount = info1.whitelistPerCount;
            approved = auditType;
            standard = info1.standard;
            typicalNFTs = info1.typicalNFTs;
            production = info1.production;
            team = info1.team;
            teamImage = info1.teamImage;
            faq = info1.faq;
            banner = info1.banner;
        };
    };

    public query func listCollections() : async [CollectionInfo] {
        Iter.toArray<CollectionInfo>(_collections.vals());
    };

    public query func getCollection(id : Principal) : async ?CollectionInfo {
        _collections.get(id);
    };

    //claim token pool
    public shared (msg) func massEnableClaim(collection : Principal, tokens : [Nat]) {
        assert (Utils.existIm<Principal>(creator_whitelist, func(v) { v == msg.caller }));
        _collectionRemainingTokens.put(collection, tokens);
    };

    public query func remaingTokens(collection : Principal) : async [Nat] {
        switch (_collectionRemainingTokens.get(collection)) {
            case (?tokens) tokens;
            case _ [];
        };
    };

    type ClaimRandomResult = Result.Result<Nat, { #CollectionNoExist; #SoldOut }>;
    let CLAIM_COUNT_THREADHOLD : Nat = 100;
    private func _canClaim(caller : Types.User, collection : Principal, count : Nat) : Bool {
        if (count > CLAIM_COUNT_THREADHOLD) {
            return false;
        };
        switch (_collections.get(collection)) {
            case (?info) {
                if (info.avaliable < count) {
                    return false;
                };
                if (Time.now() > info.whitelistTimeStart and Time.now() < info.whitelistTimeEnd) {
                    if (info.whitelistCount == 0) {
                        return false;
                    };
                    if (count > info.whitelistPerCount) {
                        return false;
                    };
                    switch (_whitelist.get(collection)) {
                        case (?whitelist) {
                            switch (whitelist.get(Types.User.toAID(caller))) {
                                case (?nat) {
                                    if (nat + count > info.whitelistPerCount) {
                                        return false;
                                    };
                                };
                                case _ {
                                    return false;
                                };
                            };
                        };
                        case _ {
                            return false;
                        };
                    };
                };
                if (Time.now() > info.starTime and Time.now() < info.endTime) {
                    switch (info.normalPerCount) {
                        case (?normalPerCount) {
                            if (normalPerCount < count) {
                                return false;
                            };
                            switch (_normalBought.get(collection)) {
                                case (?normalBought) {
                                    switch (normalBought.get(Types.User.toAID(caller))) {
                                        case (?nat) {
                                            if (nat + count > normalPerCount) {
                                                return false;
                                            };
                                        };
                                        case _ {};
                                    };
                                };
                                case _ {};
                            };
                        };
                        case _ {};
                    };
                };
            };
            case _ {
                return false;
            };
        };
        return true;
    };
    private func _claimNextToken(collection : Principal, count : Nat) : [Nat] {
        switch (_collectionRemainingTokens.get(collection)) {
            case (?remaingTokens) {
                if (remaingTokens.size() <= count) {
                    _collectionRemainingTokens.delete(collection); //从mint池取出，减少重复抢夺
                    return remaingTokens;
                };
                var _tokenIds = Buffer.Buffer<Nat>(0);
                var _remaingTokens : [Nat] = remaingTokens;
                while (_tokenIds.size() < count) {
                    var token_id = _remaingTokens[0];
                    _tokenIds.add(token_id);
                    _remaingTokens := Array.filter<Nat>(_remaingTokens, func(v) { v != token_id });
                };
                _collectionRemainingTokens.put(collection, _remaingTokens);
                return _tokenIds.toArray();
            };
            case _ {
                return [];
            };
        };
    };
    // claim
    private func _claimRandom(collection : Principal) : async ClaimRandomResult {
        switch (_collectionRemainingTokens.get(collection)) {
            case (?remaingTokens) {
                if (remaingTokens.size() > 0) {
                    var index = await _getRandomToken(remaingTokens.size());
                    let tokenId = remaingTokens[index];
                    _collectionRemainingTokens.put(collection, Array.filter<Nat>(remaingTokens, func(v) { v != tokenId })); //从mint池取出，减少重复抢夺
                    return #ok(tokenId);
                } else {
                    return #err(#SoldOut);
                };
            };
            case _ {
                return #err(#CollectionNoExist);
            };
        };
    };

    private func _getRandomToken(remaingTokenSize : Nat) : async Nat {
        var blob = await Random.blob();
        var generator = Random.Finite(blob);

        var nullNumber = generator.range(16);
        let maxValue : Nat = Nat.pow(2, 16) - 1;

        var number = Utils.unwrap(nullNumber);
        var result = number * remaingTokenSize / maxValue;
        return result;
    };

    let ledgerActor : Ledger.Self = actor (Ledger.ID);
    private let ICP_FEE : Nat64 = 10000; // e8s
    type VerifyResult = Result.Result<[Nat], { #VerifyTxErr; #VerifyTxErr1; #TxNotFound; #CollectionNoExist; #SoldOut; #Unauthorized : AccountIdentifier; #InsufficientBalance; /* Rejected by canister */ #Rejected; #PaymentReturn; #InvalidToken : TokenIdentifier; #CannotNotify : AccountIdentifier; #Other : Text;#kycNotPass;#amlNotPass;#kycorAmlNotPass; }>;
    public query (msg) func canClaim(collection : Principal, count : Nat) : async Bool {
        _canClaim(#principal(msg.caller), collection, count);
    };

    public shared (msg) func claimWithHeight(height : Nat64) : async VerifyResult {
        var collection : Principal = Principal.fromText("2vxsx-fae");
        let claimed = Buffer.Buffer<Nat>(0);
        let tokenIdentifiers = Buffer.Buffer<TokenIdentifier>(0);
        var buyer : Types.AccountIdentifier = "";
        var cid : Nat64 = 0;
        let transaction = await LedgerInterface.query_blocks(Ledger.ID,height);
        switch(transaction){
            case (?tx){
               switch (tx.operation) {
                    case (? #Transfer(transfer)) {
                        let from = AIDHex.encode(transfer.from);
                        let transferTo = AIDHex.encode(transfer.to);
                        cid := tx.memo;
                        collection := Utils.unwrap(_registry.get(cid));
                        let toAID = AviateAID.toText(AviateAID.fromPrincipal(Principal.fromActor(this), null));
                        buyer := from;
                        if (not Hex.equal(transferTo, toAID)) {
                            canistergeekLogger.logMessage(
                                "\nfunc_name: Claim" #
                                "\nerr: Reject" #
                                "\naddress: " # buyer #
                                "\ncollection: " # debug_show (Principal.toText(collection)) #
                                "\nheight: " # debug_show (height) # "\n\n"
                            );
                            return #err(#Rejected);
                        };
                        let collectionInfo = Utils.unwrap(_collections.get(collection));
                        let erc721 = actor (Principal.toText(collection)) : actor {
                            batchTransfer : shared ([Types.TransferRequest]) -> async [Types.TransferResponse];
                            getMinter : shared () -> async Principal;
                        };
                        let unit_price : Nat64 = do {
                            if (_isWhitelist(collection, #address(buyer))) {
                                collectionInfo.whitelistPrice;
                            } else {
                                collectionInfo.price;
                            };
                        };
                        let count : Nat64 = Nat64.div(transfer.amount.e8s, unit_price);
                        switch (_canClaim(#address(buyer), collection, Nat64.toNat(count))) {
                            case true {};
                            case false {
                                ignore _withdraw(height, #address(buyer));
                                canistergeekLogger.logMessage(
                                    "\nfunc_name: Claim" #
                                    "\nerr: PaymentReturn" #
                                    "\naddress: " # buyer #
                                    "\ncollection: " # debug_show (Principal.toText(collection)) #
                                    "\nheight: " # debug_show (height) # "\n\n"
                                );
                                return #err(#PaymentReturn);
                            };
                        };
                        let creater = await erc721.getMinter();
                        var claimedSize : Nat64 = 0;
                        let claimedFailed = Buffer.Buffer<Nat>(0);

                        let batchTransferRequest = Buffer.Buffer<Types.TransferRequest>(0);
                        let tokenIds = _claimNextToken(collection, Nat64.toNat(count));
                        for (tokenId in tokenIds.vals()) {
                            var tokenIdentifier = encode(collection, Nat32.fromNat(tokenId));
                            batchTransferRequest.add({
                                from = #principal(creater);
                                to = #address(buyer);
                                token = tokenIdentifier;
                                amount = 1;
                                memo = Blob.fromArray([]);
                                notify = false;
                                subaccount = null;
                            });
                        };
                        canistergeekLogger.logMessage(
                            "\nfunc_name: Claim" #
                            "\nbatchTransferRequest" # debug_show (batchTransferRequest.toArray()) # "\n\n"
                        );
                        let batchTransferRepnse = await erc721.batchTransfer(batchTransferRequest.toArray());
                        canistergeekLogger.logMessage(
                            "\nfunc_name: Claim" #
                            "\ncaller:" #debug_show (msg.caller) #
                            "\naddress: " # buyer #
                            "\nheight: " # debug_show (height) #
                            "\nbatchTransferRepnse" # debug_show (batchTransferRepnse) # "\n\n"
                        );
                        var index = 0;
                        label c for (transferResponse in batchTransferRepnse.vals()) {
                            let transferRequest = batchTransferRequest.get(index);
                            index += 1;
                            let tokenIdentifier = transferRequest.token;
                            let tokenId = Types.TokenIdentifier.getIndex(tokenIdentifier);

                            switch (transferResponse) {
                                case (#ok(ok)) {
                                    claimedSize := claimedSize + 1;
                                    claimed.add(Nat32.toNat(tokenId));
                                    tokenIdentifiers.add(tokenIdentifier);
                                };
                                case (#err(err)) {
                                    claimedFailed.add(Nat32.toNat(tokenId));
                                    canistergeekLogger.logMessage(
                                        "\nfunc_name: Claim" #
                                        "\nerr: TransferTokenErr" #
                                        "\naddress: " # buyer #
                                        "\ncollection: " # debug_show (Principal.toText(collection)) #
                                        "\nheight: " # debug_show (height) #
                                        "\ntokenid: " # debug_show (tokenId) # "\n\n"
                                    );
                                    continue c;
                                };
                            };
                        };

                        if (claimedSize != 0) {
                            let totalPrice = unit_price * claimedSize;
                            let platformFees = Nat64.div(totalPrice * platformFee.fee, 100);
                            let amount = totalPrice - platformFees;
                            addICPSettlement(#principal(creater), amount, height);
                            addICPSettlement(#principal(platformFee.account), platformFees, height);
                            _addbought(collection, buyer, Nat64.toNat(claimedSize));
                            switch (_collections.get(collection)) {
                                case (?info) {
                                    let whitelistCount : Nat = if (_isWhitelist(collection, #address(buyer))) {
                                        info.whitelistCount - Nat64.toNat(claimedSize);
                                    } else {
                                        info.whitelistCount;
                                    };
                                    _collections.put(
                                        collection,
                                        {
                                            index = info.index;
                                            id = info.id;
                                            name = info.name;
                                            featured = info.featured;
                                            featured_mobile = info.featured_mobile;
                                            description = info.description;
                                            totalSupply = info.totalSupply;
                                            avaliable = info.avaliable - Nat64.toNat(claimedSize);
                                            addTime = info.addTime;
                                            links = info.links;
                                            starTime = info.starTime;
                                            endTime = info.endTime;
                                            price = info.price;
                                            normalCount = info.normalCount;
                                            normalPerCount = info.normalPerCount;
                                            whitelistPrice = info.whitelistPrice;
                                            whitelistTimeStart = info.whitelistTimeStart;
                                            whitelistTimeEnd = info.whitelistTimeEnd;
                                            whitelistCount = whitelistCount;
                                            whitelistPerCount = info.whitelistPerCount;
                                            approved = info.approved;
                                            standard = info.standard;
                                            typicalNFTs = info.typicalNFTs;
                                            production = info.production;
                                            team = info.team;
                                            teamImage = info.teamImage;
                                            faq = info.faq;
                                            banner = info.banner;
                                        },
                                    );
                                };
                                case _ {};
                            };
                        };
                        //Refund of failed amounts
                        if (claimed.size() < Nat64.toNat(count)) {
                            addICPRefundSettlement(buyer, (count -claimedSize) * unit_price, height);
                            canistergeekLogger.logMessage(
                                "\nfunc_name: Claim" #
                                "\nerr: Refund" #
                                "\naccount: " # buyer #
                                "\ncollection: " # debug_show (Principal.toText(collection)) #
                                "\nheight: " # debug_show (height) #
                                "\nprice: " # debug_show ((count - claimedSize) * unit_price) # "\n\n"
                            );
                        };
                        if (claimedFailed.size() > 0) {
                            switch (_collectionRemainingTokens.get(collection)) {
                                case (?remainingTokens) {
                                    _collectionRemainingTokens.put(collection, Array.append<Nat>(remainingTokens, claimedFailed.toArray()));

                                };
                                case _ {
                                    _collectionRemainingTokens.put(collection, claimedFailed.toArray());
                                };
                            };
                        };
                    };
                    case _{return #err(#TxNotFound);};
               }
            };
            case _ {return #err(#TxNotFound);};
        };

        let collectionInfo = Utils.unwrap(_collections.get(collection));
        let unit_price : Price = do {
            if (_isWhitelist(collection, #address(buyer))) {
                collectionInfo.whitelistPrice;
            } else {
                collectionInfo.price;
            };
        };
        var to : ?Principal = null;
        if (Types.User.toAID(#principal(msg.caller)) == buyer) {
            to := ?msg.caller;
        };
        return #ok(claimed.toArray());
    };

    private func _sendICP(to : Principal, amount : Price, memo : Nat64) : async Bool {
        if (amount == 0) {
            return true;
        };

        let res = await ledgerActor.transfer({
            memo = memo;
            from_subaccount = null;
            to = AviateAID.fromPrincipal(to, null);
            amount = { e8s = amount - ICP_FEE };
            fee = { e8s = ICP_FEE };
            created_at_time = ?{
                timestamp_nanos = Nat64.fromNat(Int.abs(Time.now()));
            };
        });
        switch (res) {
            case (#Ok(height)) {
                return true;
            };
            case (#Err(_)) {
                return false;
            };
        };
    };

    private func _sendICPToUser(to : AccountIdentifier, amount : Price, memo : Nat64) : async Bool {
        let res = await ledgerActor.transfer({
            memo = memo;
            from_subaccount = null;
            to = Blob.fromArray(AIDHex.decode(to));
            amount = { e8s = amount - ICP_FEE };
            fee = { e8s = ICP_FEE };
            created_at_time = ?{
                timestamp_nanos = Nat64.fromNat(Int.abs(Time.now()));
            };
        });
        switch (res) {
            case (#Ok(height)) {
                return true;
            };
            case (#Err(_)) {
                return false;
            };
        };
    };


    system func preupgrade() {
        _registryArray := Iter.toArray(_registry.entries());
        _collectionArray := Iter.toArray(_collections.entries());
        _collectionRemainingTokenArray := Iter.toArray(_collectionRemainingTokens.entries());
        let entries : HashMap.HashMap<Principal, [(AccountIdentifier, Nat)]> = HashMap.HashMap<Principal, [(AccountIdentifier, Nat)]>(10, Principal.equal, Principal.hash);
        for ((key : Principal, value : HashMap.HashMap<AccountIdentifier, Nat>) in _whitelist.entries()) {
            let inner : [(AccountIdentifier, Nat)] = Iter.toArray<(AccountIdentifier, Nat)>(value.entries());
            entries.put(key, inner);
        };
        _whitelistArray := Iter.toArray(entries.entries());
        let boughtEntries : HashMap.HashMap<Principal, [(AccountIdentifier, Nat)]> = HashMap.HashMap<Principal, [(AccountIdentifier, Nat)]>(10, Principal.equal, Principal.hash);
        for ((key : Principal, value : HashMap.HashMap<AccountIdentifier, Nat>) in _normalBought.entries()) {
            let inner : [(AccountIdentifier, Nat)] = Iter.toArray<(AccountIdentifier, Nat)>(value.entries());
            boughtEntries.put(key, inner);
        };
        _normalBoughtArray := Iter.toArray(boughtEntries.entries());
        _icpRefundSettlements_entries := Iter.toArray(_icpRefundSettlements.entries());
        _icpSettlements_entries := Iter.toArray(_icpSettlements.entries());
    };

    system func postupgrade() {
        _registry := HashMap.fromIter<Nat64, Principal>(_registryArray.vals(), _registryArray.size(), Nat64.equal, _hash);
        _collectionRemainingTokens := HashMap.fromIter<Principal, [Nat]>(_collectionRemainingTokenArray.vals(), _collectionArray.size(), Principal.equal, Principal.hash);
        for ((key : Principal, value : [(AccountIdentifier, Nat)]) in _whitelistArray.vals()) {
            let inner : HashMap.HashMap<AccountIdentifier, Nat> = HashMap.fromIter<AccountIdentifier, Nat>(Iter.fromArray<(AccountIdentifier, Nat)>(value), 0, Text.equal, Text.hash);
            _whitelist.put(key, inner);
        };
        _icpRefundSettlements_entries := [];
        canistergeekLogger.postupgrade(_canistergeekLoggerUD);
        _canistergeekLoggerUD := null;
        canistergeekLogger.setMaxMessagesCount(5000);
        canistergeekLogger.logMessage("postupgrade");
    };


    private func _withdraw(height : Nat64, user : Types.User) : async () {
        let transaction = await LedgerInterface.query_blocks(Ledger.ID,height);
        switch(transaction){
            case (?tx){
               switch (tx.operation) {
                    case (? #Transfer(transfer)) {
                        let from = Types.User.toAID(user);
                        let transferfrom = AIDHex.encode(transfer.from);
                        if (transferfrom == from) {
                            addICPRefundSettlement(from, transfer.amount.e8s, height);
                        };
                    };
                    case _ {};
               };
            };
            case _ {};
        };
    };

    private stable var creator_whitelist : [Principal] = [];
    private stable var second_creator_whitelist : [Principal] = [];

    public shared (msg) func addCreator_whitelist(whitelist : [Principal]) : async [Principal] {
        assert (msg.caller == _owner);
        creator_whitelist := Array.append(creator_whitelist, whitelist);
        creator_whitelist;
    };

    public shared (msg) func delCreator_whitelist(whitelists : [Principal]) : async [Principal] {
        assert (msg.caller == _owner);
        for (whitelist in whitelists.vals()) {
            creator_whitelist := Array.filter<Principal>(creator_whitelist, func(v) { v != whitelist });
        };
        creator_whitelist;
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
    // assert(Utils.existIm<Principal>(creator_whitelist,func(v){v == msg.caller}));
    public type TokenIndex = Nat32;
    private let prefix : [Nat8] = [10, 116, 105, 100]; // \x0A "tid"
    private func encode(canisterId : Principal, tokenIndex : TokenIndex) : Text {
        let rawTokenId = Array.flatten<Nat8>([
            prefix,
            Blob.toArray(AviatePrincipal.toBlob(canisterId)),
            Binary.BigEndian.fromNat32(tokenIndex),
        ]);

        AviatePrincipal.toText(AviatePrincipal.fromBlob(Blob.fromArray(rawTokenId)));
    };


    type ICPSale = Types.ICPSale;
    type SettleICPResult = Types.SettleICPResult;
    private stable var _icpSaleIndex : Nat = 1;
    private stable var _icpSettlements_entries : [(Nat, ICPSale)] = [];
    private var _icpSettlements : TrieMap.TrieMap<Nat, ICPSale> = TrieMap.fromEntries(_icpSettlements_entries.vals(), Nat.equal, Hash.hash);

    public query func getICPSettlements() : async [(Nat, ICPSale)] {
        Iter.toArray(_icpSettlements.entries());
    };

    public shared (msg) func settleICP(index : Nat) : async SettleICPResult {
        // assert(Utils.existIm<Principal>(creator_whitelist,func(v){v == msg.caller}));
        switch (_icpSettlements.get(index)) {
            case (?settlement) {
                // process
                if (settlement.retry >= 3) {
                    return #err(#RetryExceed);
                };
                // 先删除防止并发读
                _icpSettlements.delete(index);
                // 删掉
                try {

                    var resp : Bool = false;
                    switch (settlement.user) {
                        case (#principal(pid)) {
                            resp := await _sendICP(pid, settlement.price, settlement.memo);
                        };
                        case (#address(aid)) {
                            resp := await _sendICPToUser(aid, settlement.price, settlement.memo);
                        };
                    };
                    if (not resp) {
                        canistergeekLogger.logMessage(
                            "\nfunc_name: settleICP" #
                            "\nerr: SettleErr" #
                            "\nindex: " # debug_show (index) # "\n\n"
                        );
                        // retry
                        _icpSettlements.put(
                            index,
                            {
                                user = settlement.user;
                                price = settlement.price;
                                retry = settlement.retry + 1;
                                memo = settlement.memo;
                                token = Types.icpToken;
                            },
                        );
                        return #err(#SettleErr);
                    } else {
                        return #ok();
                    };
                } catch (e) {
                    canistergeekLogger.logMessage(
                        "\nfunc_name: settleICP" #
                        "\nerr: SettleErr" #
                        "\nindex: " # debug_show (index) # "\n\n"
                    );
                    _icpSettlements.put(
                        index,
                        {
                            user = settlement.user;
                            price = settlement.price;
                            retry = settlement.retry + 1;
                            memo = settlement.memo;
                            token = Types.icpToken;
                        },
                    );
                    return #err(#SettleErr);
                };
            };
            case (_) return #err(#NoSettleICP);
        };
    };

    private func addICPSettlement(_user : User, _price : Nat64, memo : Nat64) {
        _icpSettlements.put(
            _icpSaleIndex,
            {
                user = _user;
                price = _price;
                retry = 0;
                memo = memo;
                token = Types.icpToken;
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

    public shared (msg) func settleICPRefund(index : Nat) : async SettleICPResult {
        // assert(Utils.existIm<Principal>(creator_whitelist,func(v){v == msg.caller}));
        switch (_icpRefundSettlements.get(index)) {
            case (?settlement) {
                // process
                if (settlement.retry >= 3) {
                    return #err(#RetryExceed);
                };
                // 先删除防止并发读
                _icpRefundSettlements.delete(index);
                // 删掉
                try {
                    let resp = await _sendICPToUser(settlement.user, settlement.price, settlement.memo);
                    if (not resp) {
                        _icpRefundSettlements.put(
                            index,
                            {
                                user = settlement.user;
                                price = settlement.price;
                                retry = settlement.retry + 1;
                                memo = settlement.memo;
                                token = Types.icpToken;
                            },
                        );
                        return #err(#SettleErr);
                    };
                    return #ok();
                } catch (e) {
                    Debug.print(debug_show ("try cath error: "));
                    _icpRefundSettlements.put(
                        index,
                        {
                            user = settlement.user;
                            price = settlement.price;
                            retry = settlement.retry + 1;
                            memo = settlement.memo;
                            token = Types.icpToken;
                        },
                    );
                    return #err(#SettleErr);
                };
            };
            case (_) return #err(#NoSettleICP);
        };
    };

    private func addICPRefundSettlement(_user : AccountIdentifier, _price : Nat64, memo : Nat64) {
        _icpRefundSettlements.put(
            _icpRefundIndex,
            {
                user = _user;
                price = _price;
                retry = 0;
                memo = memo;
                token = Types.icpToken;
            },
        );
        _icpRefundIndex += 1;
    };


    public shared (msg) func flushICPSettlement() : async () {
        assert (msg.caller == _owner);
        _icpSettlements := TrieMap.TrieMap<Nat, ICPSale>(Nat.equal, Hash.hash);
    };

    public shared (msg) func flushICPRefundSettlement() : async () {
        assert (msg.caller == _owner);
        _icpRefundSettlements := TrieMap.TrieMap<Nat, ICPRefund>(Nat.equal, Hash.hash);
    };

    public query (msg) func getConfig() : async {
        owner : Principal;
        platformFeeAccount : Principal;
        ledger : Text;
    } {
        assert (msg.caller == _owner);
        {
            owner = owner;
            platformFeeAccount = platformFeeAccount;
            ledger = Ledger.ID;
        };
    };
};
