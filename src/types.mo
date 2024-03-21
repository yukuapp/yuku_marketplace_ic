import Text "mo:base/Text";
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Time "mo:base/Time";
import Int "mo:base/Int";
import Hash "mo:base/Hash";
import Blob "mo:base/Blob";
import Array "mo:base/Array";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Buffer "mo:base/Buffer";
import Iter "mo:base/Iter";
import Result "mo:base/Result";
import Char "mo:base/Char";
import Ext "mo:ext/Ext";
import ERC20_Ext "mo:ext/ERC20_Ext";
import Ledger "ledger";

module {
    ///collection and token721
    public type Img = Text;
    public type File = Text;
    public type Category = Text;
    public type UserId = Principal;
    public type TokenSpec = {
        canister : Text;
        fee : Nat64;
        decimal : Nat;
        symbol : Text;
    };

    public let icpToken : TokenSpec = {
        canister = Ledger.ID;
        fee = 10000;
        decimal = 8;
        symbol = "ICP";
    };
    public type ICPSale = {
        user : User;
        price : Nat64;
        retry : Nat64;
        memo : Nat64;
        token : TokenSpec;
    };
    public type ICPRefund = {
        user : AccountIdentifier;
        price : Nat64;
        retry : Nat64;
        memo : Nat64;
        token : TokenSpec;
    };
    public type SettleICPResult = Result.Result<(), { #RetryExceed; #NoSettleICP; #SettleErr }>;
    public type Standard = {
        #ext;
        #ogy;
    };
    public type CollectionErr = {
        #maxCollNum;
        #perMaxCollNum;
        #guestCannotCreateCollection;
    };

    public type CollectionInit = {
        name : Text;
        logo : ?Img;
        banner : ?Img;
        featured : ?Img;
        url : ?Text;
        description : ?Text;
        category : ?Category;
        links : ?Links;
        royalties : Royality;
        releaseTime : ?Time.Time;
        isVisible : Bool;
        openTime : ?Time.Time;
        standard : Standard;
    };

    public type Links = {
        yoursite : ?Text;
        discord : ?Text;
        twitter : ?Text;
        instagram : ?Text;
        medium : ?Text;
        telegram : ?Text;
    };

    public type CollectionInfo = {
        name : Text;
        logo : ?Img;
        banner : ?Img;
        featured : ?Img;
        url : ?Text;
        description : ?Text;
        category : ?Category;
        links : ?Links;
        royalties : Royality;
        canisterId : Principal;
        releaseTime : ?Time.Time;
        isVisible : Bool;
        creator : UserId;
        standard : Standard;
    };
    public type Royality = {
        rate : Nat64;
        precision : Nat64;
    };

    public type PlatformFee = {
        var fee : Nat64;
        var account : Principal;
        var precision : Nat64;
    };

    public type AddCart = {
        tokenIdentifier : TokenIdentifier;
        nftName : Text;
        nftUrl : Text;
    };

    public type ShowCart = {
        tokenIdentifier : TokenIdentifier;
        collectionName : Text;
        price : Nat64;
        nftName : Text;
        nftUrl : Text;
    };

    public type Price = Nat64;
    public type OfferId = Nat;
    public type DutchAuctionId = Nat;
    public type Fee = {
        platform : Price;
        royalties : Price;
    };

    public type Fixed = {
        price : Price;
        seller : Principal;
        fee : Fee;
        tokenIdentifier : TokenIdentifier;
        token : TokenSpec;
    };

    public type Auction = {
        startPrice : Price;
        seller : Principal;
        resevePrice : ?Price;
        ttl : Int;
        highestBidder : ?Principal;
        highestPrice : ?Price;
        fee : Fee;
        tokenIdentifier : TokenIdentifier;
    };

    public type DutchAuction = {
        startPrice : Price;
        floorPrice : Price;
        startTime : Time.Time;
        endTime : Time.Time;
        reducePrice : Price;
        reduceTime : Nat64;
        seller : Principal;
        payee : User;
        fee : Fee;
        tokenIdentifier : TokenIdentifier;
        token : TokenSpec;
    };

    public type Listing = {
        #unlist;
        #fixed : Fixed;
        #auction : Auction;
        #dutchAuction : DutchAuction;
    };

    public type NFTInfo = {
        views : Nat;
        lastPrice : Price;
        favoriters : [Principal];
        listing : Listing;
        listTime : ?Time.Time;
    };


    //Ext
    public type AccountIdentifier = Ext.AccountIdentifier;
    public type User = Ext.User;
    public type SubAccount = Ext.SubAccount;
    public type TokenIndex = Ext.TokenIndex;
    public type TokenIdentifier = Ext.TokenIdentifier;
    public type Balance = Ext.Balance;
    public type BalanceRequest = Ext.Core.BalanceRequest;
    public type BalanceResponse = Ext.Core.BalanceResponse;
    public type TransferRequest = Ext.Core.TransferRequest;
    public type BatchTransferRequest = Ext.Core.BatchTransferRequest;
    public type TransferResponse = Ext.Core.TransferResponse;
    public type AllowanceRequest = Ext.Allowance.AllowanceRequest;
    public type ApproveRequest = Ext.Allowance.ApproveRequest;
    public type Metadata = Ext.Metadata;
    public type MintRequest = Ext.MintRequest;
    public type Extension = Ext.Core.Extension;
    public type CommonError = Ext.Core.CommonError;

    public module TokenIdentifier = {
        public let equal = Ext.TokenIdentifier.equal;
        public let hash = Ext.TokenIdentifier.hash;
        public let getCollectionId = Ext.TokenIdentifier.getCollectionId;
        public let isPrincipal = Ext.TokenIdentifier.isPrincipal;
        public let getIndex = Ext.TokenIdentifier.getIndex;
        public let decode = Ext.TokenIdentifier.decode;
    };
    public module AccountIdentifier = {
        public let equal = Ext.AccountIdentifier.equal;
        public let hash = Ext.AccountIdentifier.hash;
        public let fromPrincipal = Ext.AccountIdentifier.fromPrincipal;
    };
    public module User = {
        public let toAID = Ext.User.toAID;
        public let toPrincipal = Ext.User.toPrincipal;
        public let equal = Ext.User.equal;
        public let hash = Ext.User.hash;
    };

    public type Collection = actor {
        mintNFT : shared MintRequest -> async TokenIndex;
        transfer : shared TransferRequest -> async TransferResponse;
        bearer : shared query TokenIdentifier -> async Result.Result<AccountIdentifier, CommonError>;
        getMinter : shared query () -> async Principal;
        approveAll : shared [ApproveRequest] -> async [TokenIndex];
        allowance : shared query AllowanceRequest -> async Result.Result<Balance, CommonError>;
    };

    public type Yumi = actor {
        importCollection : (Principal, Text, CollectionInit) -> async Result.Result<(), CollectionErr>;
    };

    public type PageParam = {
        page : Nat;
        pageCount : Nat;
    };

    public type Topic = {
        #claim;
    };
    //launchpad
    public type LaunchpadCollectionInfo = {
        id : Principal;
        index : Nat64;
        name : Text;
        featured : Text;
        featured_mobile : Text;
        description : Text;
        totalSupply : Nat;
        avaliable : Nat;
        addTime : Time.Time;
        links : ?Links;
        starTime : Time.Time;
        endTime : Time.Time;
        price : Price;
        normalCount : Nat;
        normalPerCount : ?Nat;
        whitelistPrice : Price;
        whitelistTimeStart : Time.Time;
        whitelistTimeEnd : Time.Time;
        whitelistCount : Nat;
        whitelistPerCount : Nat;
        approved : Text;
        standard : Standard;
        typicalNFTs : [{
            NFTName : Text;
            NFTUrl : Text;
            Canister : Principal;
            TokenIndex : TokenIndex;
        }];
        production : Text;
        team : Text;
        teamImage : [Text];
        faq : [{ Question : Text; Answer : Text }];
        banner : Text;
    };

    public type TransferError = {
        #BadFee : { expected_fee : Ledger.ICP };
        #InsufficientFunds : { balance : Ledger.ICP };
        #TxTooOld : { allowed_window_nanos : Nat64 };
        #TxCreatedInFuture;
        #TxDuplicate : { duplicate_of : Ledger.BlockIndex };
        #Other : Text;
    };
    public type TransferResult = Result.Result<Ledger.BlockIndex, TransferError>;
};
