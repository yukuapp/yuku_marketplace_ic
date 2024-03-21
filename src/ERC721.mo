import Principal "mo:base/Principal";
import Iter "mo:base/Iter";
import HashMap "mo:base/HashMap";
import Cycles "mo:base/ExperimentalCycles";
import Result "mo:base/Result";
import TrieSet "mo:base/TrieSet";
import Text "mo:base/Text";
import Buffer "mo:base/Buffer";
import Hash "mo:base/Hash";
import Float "mo:base/Float";
import Array "mo:base/Array";
import Debug "mo:base/Debug";
import Int "mo:base/Int";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Blob "mo:base/Blob";
import Option "mo:base/Option";
import Ext "mo:ext/Ext";
import Json "mo:json/JSON";
import Http "./http";
import Binary "mo:encoding/Binary";
import AviatePrincipal "mo:principal/Principal";
import Nat "mo:base/Nat";

shared (install) actor class ERC721(init_minter : Principal) = this {
  type Result<Ok, Err> = Result.Result<Ok, Err>;

  type HashMap<K, V> = HashMap.HashMap<K, V>;

  type AccountIdentifier = Ext.AccountIdentifier;
  type User = Ext.User;
  type SubAccount = Ext.SubAccount;
  type TokenIndex = Ext.TokenIndex;
  type TokenIdentifier = Ext.TokenIdentifier;
  type Balance = Ext.Balance;
  type BalanceRequest = Ext.Core.BalanceRequest;
  type BalanceResponse = Ext.Core.BalanceResponse;
  type TransferRequest = Ext.Core.TransferRequest;
  type TransferResponse = Ext.Core.TransferResponse;
  type AllowanceRequest = Ext.Allowance.AllowanceRequest;
  type ApproveRequest = Ext.Allowance.ApproveRequest;
  type Metadata = Ext.Metadata;
  type MintRequest = Ext.MintRequest;
  type Extension = Ext.Core.Extension;
  type CommonError = Ext.Core.CommonError;
  type Score = Float;

  private let EXTENSIONS : [Extension] = [
    "@ext/common",
    "@ext/allowance",
    "@ext/nonfungible",
  ];

  private stable var _registryState : [(TokenIndex, AccountIdentifier)] = [];
  private var _registry : HashMap<TokenIndex, AccountIdentifier> = HashMap.fromIter(_registryState.vals(), 0, Ext.Core.TokenIndex.equal, Ext.Core.TokenIndex.hash);

  private stable var _allowancesState : [(TokenIndex, Principal)] = [];
  private var _allowances : HashMap<TokenIndex, Principal> = HashMap.fromIter(_allowancesState.vals(), 0, Ext.Core.TokenIndex.equal, Ext.Core.TokenIndex.hash);

  private stable var _tokenMetadataState : [(TokenIndex, Metadata)] = [];
  private var _tokenMetadata : HashMap<TokenIndex, Metadata> = HashMap.fromIter(_tokenMetadataState.vals(), 0, Ext.Core.TokenIndex.equal, Ext.Core.TokenIndex.hash);

  private stable var _supply : Balance = 0;
  private stable var _minter : Principal = init_minter;
  private stable var _nextTokenId : TokenIndex = 0;

  system func preupgrade() {
    _registryState := Iter.toArray(_registry.entries());
    _allowancesState := Iter.toArray(_allowances.entries());
    _tokenMetadataState := Iter.toArray(_tokenMetadata.entries());
    _propertiesArr := Iter.toArray(_properties.entries());
    _rarityScoresState := Iter.toArray(_rarityScores.entries());
  };

  system func postupgrade() {
    _registryState := [];
    _allowancesState := [];
    _tokenMetadataState := [];
    _propertiesArr := [];

    _rarityScoresState := [];
  };

  public shared (msg) func setMinter(minter : Principal) : async () {
    assert (msg.caller == _minter);
    _minter := minter;
  };

  public shared (msg) func mintNFT(request : MintRequest) : async TokenIndex {
    assert (msg.caller == _minter);
    let receiver = Ext.User.toAID(request.to);
    let token = _nextTokenId;
    let md : Metadata = #nonfungible({
      metadata = request.metadata;
    });
    _registry.put(token, receiver);
    _tokenMetadata.put(token, md);
    _addProperty(token, request.metadata);
    _supply := _supply + 1;
    _nextTokenId := _nextTokenId + 1;
    _setScoreOfTokenId(7);
    return token;
  };

  public shared (msg) func transfer(request : TransferRequest) : async TransferResponse {
    if (request.amount != 1) {
      return #err(#Other("Must use amount of 1"));
    };
    if (Ext.TokenIdentifier.isPrincipal(request.token, Principal.fromActor(this)) == false) {
      return #err(#InvalidToken(request.token));
    };
    let token = Ext.TokenIdentifier.getIndex(request.token);
    let owner = Ext.User.toAID(request.from);
    let spender = Ext.AccountIdentifier.fromPrincipal(msg.caller, request.subaccount);
    let receiver = Ext.User.toAID(request.to);

    switch (_registry.get(token)) {
      case (?token_owner) {
        if (Ext.AccountIdentifier.equal(owner, token_owner) == false) {
          return #err(#Unauthorized(owner));
        };
        if (Ext.AccountIdentifier.equal(owner, spender) == false) {
          switch (_allowances.get(token)) {
            case (?token_spender) {
              if (Principal.equal(msg.caller, token_spender) == false) {
                return #err(#Unauthorized(spender));
              };
            };
            case (_) {
              return #err(#Unauthorized(spender));
            };
          };
        };
        _allowances.delete(token);
        _registry.put(token, receiver);
        return #ok(request.amount);
      };
      case (_) {
        return #err(#InvalidToken(request.token));
      };
    };
  };

  public shared (msg) func batchTransfer(requests : [TransferRequest]) : async [TransferResponse] {
    let buff = Buffer.Buffer<TransferResponse>(0);
    label c for (request in requests.vals()) {
      if (request.amount != 1) {
        buff.add(#err(#Other("Must use amount of 1")));
        continue c;
      };
      if (Ext.TokenIdentifier.isPrincipal(request.token, Principal.fromActor(this)) == false) {
        buff.add(#err(#InvalidToken(request.token)));
        continue c;
      };
      let token = Ext.TokenIdentifier.getIndex(request.token);
      let owner = Ext.User.toAID(request.from);
      let spender = Ext.AccountIdentifier.fromPrincipal(msg.caller, request.subaccount);
      let receiver = Ext.User.toAID(request.to);

      switch (_registry.get(token)) {
        case (?token_owner) {
          if (Ext.AccountIdentifier.equal(owner, token_owner) == false) {
            buff.add(#err(#Unauthorized(owner)));
            continue c;
          };
          if (Ext.AccountIdentifier.equal(owner, spender) == false) {
            switch (_allowances.get(token)) {
              case (?token_spender) {
                if (Principal.equal(msg.caller, token_spender) == false) {
                  buff.add(#err(#Unauthorized(spender)));
                  continue c;
                };
              };
              case (_) {
                buff.add(#err(#Unauthorized(spender)));
                continue c;
              };
            };
          };
          _allowances.delete(token);
          _registry.put(token, receiver);
          buff.add(#ok(request.amount));
        };
        case (_) {
          buff.add(#err(#InvalidToken(request.token)));
          continue c;
        };
      };
    };
    buff.toArray();
  };

  public shared (msg) func approve(request : ApproveRequest) : async Bool {
    if (Ext.TokenIdentifier.isPrincipal(request.token, Principal.fromActor(this)) == false) {
      return false;
    };
    let token = Ext.TokenIdentifier.getIndex(request.token);
    let owner = Ext.AccountIdentifier.fromPrincipal(msg.caller, request.subaccount);
    switch (_registry.get(token)) {
      case (?token_owner) {
        if (Ext.AccountIdentifier.equal(owner, token_owner) == false) {
          return false;
        };
        _allowances.put(token, request.spender);
        return true;
      };
      case (_) {
        return false;
      };
    };
  };

  public query func getMinter() : async Principal {
    _minter;
  };

  public query func extensions() : async [Extension] {
    EXTENSIONS;
  };

  public query func balance(request : BalanceRequest) : async BalanceResponse {
    if (Ext.TokenIdentifier.isPrincipal(request.token, Principal.fromActor(this)) == false) {
      return #err(#InvalidToken(request.token));
    };
    let token = Ext.TokenIdentifier.getIndex(request.token);
    let aid = Ext.User.toAID(request.user);
    switch (_registry.get(token)) {
      case (?token_owner) {
        if (Ext.AccountIdentifier.equal(aid, token_owner) == true) {
          return #ok(1);
        } else {
          return #ok(0);
        };
      };
      case (_) {
        return #err(#InvalidToken(request.token));
      };
    };
  };

  public query func allowance(request : AllowanceRequest) : async Result<Balance, CommonError> {
    if (Ext.TokenIdentifier.isPrincipal(request.token, Principal.fromActor(this)) == false) {
      return #err(#InvalidToken(request.token));
    };
    let token = Ext.TokenIdentifier.getIndex(request.token);
    let owner = Ext.User.toAID(request.owner);
    switch (_registry.get(token)) {
      case (?token_owner) {
        if (Ext.AccountIdentifier.equal(owner, token_owner) == false) {
          return #err(#Other("Invalid owner"));
        };
        switch (_allowances.get(token)) {
          case (?token_spender) {
            if (Principal.equal(request.spender, token_spender) == true) {
              return #ok(1);
            } else {
              return #ok(0);
            };
          };
          case (_) {
            return #ok(0);
          };
        };
      };
      case (_) {
        return #err(#InvalidToken(request.token));
      };
    };
  };

  public query func bearer(token : TokenIdentifier) : async Result<AccountIdentifier, CommonError> {
    if (Ext.TokenIdentifier.isPrincipal(token, Principal.fromActor(this)) == false) {
      return #err(#InvalidToken(token));
    };
    let tokenind = Ext.TokenIdentifier.getIndex(token);
    switch (_registry.get(tokenind)) {
      case (?token_owner) {
        return #ok(token_owner);
      };
      case (_) {
        return #err(#InvalidToken(token));
      };
    };
  };

  public query func supply(token : TokenIdentifier) : async Result.Result<Balance, CommonError> {
    #ok(_supply);
  };

  public query func getRegistry() : async [(TokenIndex, AccountIdentifier)] {
    Iter.toArray(_registry.entries());
  };

  public query func getAllowances() : async [(TokenIndex, Principal)] {
    Iter.toArray(_allowances.entries());
  };

  public query func getTokens() : async [(TokenIndex, Metadata)] {
    Iter.toArray(_tokenMetadata.entries());
  };

  public query func metadata(token : TokenIdentifier) : async Result<Metadata, CommonError> {
    if (Ext.TokenIdentifier.isPrincipal(token, Principal.fromActor(this)) == false) {
      return #err(#InvalidToken(token));
    };
    let tokenind = Ext.TokenIdentifier.getIndex(token);
    switch (_tokenMetadata.get(tokenind)) {
      case (?token_metadata) {
        return #ok(token_metadata);
      };
      case (_) {
        return #err(#InvalidToken(token));
      };
    };
  };

  public func acceptCycles() : async () {
    let available = Cycles.available();
    let accepted = Cycles.accept(available);
    assert (accepted == available);
  };

  public query func availableCycles() : async Nat {
    return Cycles.balance();
  };

  type Property = {
    trait_type : Text;
    value : Text;
  };

  func _equal(p1 : Property, p2 : Property) : Bool {
    Text.equal(p1.trait_type #p1.value, p2.trait_type #p2.value);
  };

  func _hash(p : Property) : Hash.Hash {
    Text.hash(p.trait_type #p.value);
  };

  private stable var _propertiesArr : [(Property, [TokenIndex])] = [];
  // private var _properties = HashMap<Property,[TokenIndex]>(0,_equal,_hash);
  private var _properties : HashMap<Property, [TokenIndex]> = HashMap.fromIter(_propertiesArr.vals(), 0, _equal, _hash);

  public shared (msg) func initproperties(start : TokenIndex, end : TokenIndex) : async () {
    assert (msg.caller == _minter);
    for (i in Iter.range(Nat32.toNat(start), Nat32.toNat(end))) {
      let tokenIndex = Nat32.fromNat(i);
      switch (_tokenMetadata.get(tokenIndex)) {
        case (? #nonfungible(metadata)) {
          _addProperty(tokenIndex, metadata.metadata);
        };
        case _ {};
      };
    };
  };

  // public query func getProperties()  : async [Property]{
  //   TrieSet.toArray<Property>(TrieSet.fromArray<Property>(Iter.toArray(_properties.keys()),_hash,_equal));
  // };

  public query func getProperties() : async [(Text, [(Text, Nat)])] {
    let properties : [(Property, [TokenIndex])] = Iter.toArray(_properties.entries());
    let propertyMap = HashMap.HashMap<Text, [(Text, Nat)]>(0, Text.equal, Text.hash);
    for (({ trait_type; value }, tokenIndexs) in properties.vals()) {
      switch (propertyMap.get(trait_type)) {
        case (?values) {
          let _values = Array.append(values, Array.make(value, tokenIndexs.size()));
          propertyMap.put(trait_type, _values);
        };
        case _ {
          propertyMap.put(trait_type, Array.make(value, tokenIndexs.size()));
        };
      };
    };
    Iter.toArray(propertyMap.entries());
  };

  public query func lookProperties() : async [(Property, [TokenIndex])] {
    Iter.toArray(_properties.entries());
  };

  public query func getTokensByProperties(properties : [(Text, [Text])]) : async [(TokenIndex, Metadata)] {
    var result = TrieSet.fromArray<(TokenIndex, Metadata)>(Iter.toArray<(TokenIndex, Metadata)>(_tokenMetadata.entries()), _elemHash, _elemEqual);
    if (properties.size() > 0) {
      for ((trait_type, values) in properties.vals()) {
        var inner = TrieSet.empty<(TokenIndex, Metadata)>();
        for (value in values.vals()) {
          switch (_properties.get({ trait_type = trait_type; value = value })) {
            case (?tokenIndexs) {
              let tmpIds = _getTokensByIds(tokenIndexs);
              let tmpSet = TrieSet.fromArray<(TokenIndex, Metadata)>(tmpIds, _elemHash, _elemEqual);
              inner := TrieSet.union<(TokenIndex, Metadata)>(inner, tmpSet, _elemEqual);
            };
            case _ {};
          };
        };
        result := TrieSet.intersect<(TokenIndex, Metadata)>(result, inner, _elemEqual);
      };
    };
    TrieSet.toArray<(TokenIndex, Metadata)>(result);
  };

  func _elemHash((tokenIndex, metadata) : (TokenIndex, Metadata)) : Hash.Hash {
    tokenIndex;
  };

  func _elemEqual((tokenIndex1, metadata1) : (TokenIndex, Metadata), (tokenIndex2, metadata2) : (TokenIndex, Metadata)) : Bool {
    tokenIndex1 == tokenIndex2;
  };

  public query func getTokensByIds(tokenIndexs : [TokenIndex]) : async [(TokenIndex, Metadata)] {
    _getTokensByIds(tokenIndexs);
  };

  func _addProperty(tokenIndex : TokenIndex, metadata : ?Blob) {
    let properties = _initProperty(metadata);
    for (property in properties.vals()) {
      switch (_properties.get(property)) {
        case (?tokenIndexs) {
          let _tokenIndexs = Array.append(tokenIndexs, [tokenIndex]);
          _properties.put(property, _tokenIndexs);
        };
        case _ {
          _properties.put(property, Array.make(tokenIndex));
        };
      };
    };
  };

  func _initProperty(metadata : ?Blob) : [Property] {
    let buff = Buffer.Buffer<Property>(0);
    let json = switch (metadata) {
      case (?blob) {
        switch (Text.decodeUtf8(blob)) {
          case (?text) {
            text;
          };
          case _ {
            return buff.toArray();
          };
        };
      };
      case _ {
        return buff.toArray();
      };
    };

    let p = Json.Parser();
    switch (p.parse(json)) {
      case (? #Object(v)) {
        switch (v.get("attributes")) {
          case (? #Array(v)) {
            for (value in v.vals()) {
              switch (value) {
                case (#Object(v)) {
                  switch (v.get("trait_type"), v.get("value")) {
                    case (? #String(trait_type), ? #String(value)) {
                      buff.add({
                        trait_type = trait_type;
                        value = value;
                      });
                    };
                    case (? #String(trait_type), ? #Number(value)) {
                      buff.add({
                        trait_type = trait_type;
                        value = Int.toText(value);
                      });
                    };
                    case _ {
                      Debug.print(debug_show ("trait_type or value is null"));
                    };
                  };
                };
                case _ {};
              };
            };
          };
          case _ {};
        };
      };
      case _ {};
    };
    buff.toArray();
  };

  private func _getTokensByIds(tokenIndexs : [TokenIndex]) : [(TokenIndex, Metadata)] {
    var buff = Buffer.Buffer<(TokenIndex, Metadata)>(0);
    for (tokenIndex in tokenIndexs.vals()) {
      switch (_tokenMetadata.get(tokenIndex)) {
        case (?metadata) {
          buff.add((tokenIndex, metadata));
        };
        case _ {};
      };
    };
    buff.toArray();
  };

  public shared (msg) func batchMintNFT(requests : [MintRequest]) : async [TokenIndex] {
    assert (msg.caller == _minter);
    var buffer = Buffer.Buffer<TokenIndex>(0);
    for (request in requests.vals()) {
      let receiver = Ext.User.toAID(request.to);
      let token = _nextTokenId;
      let md : Metadata = #nonfungible({
        metadata = request.metadata;
      });
      _registry.put(token, receiver);
      _tokenMetadata.put(token, md);
      _addProperty(token, request.metadata);
      _supply := _supply + 1;
      _nextTokenId := _nextTokenId + 1;
      _setScoreOfTokenId(7);
      buffer.add(token);
    };
    buffer.toArray();
  };

  public shared (msg) func approveAll(requests : [ApproveRequest]) : async [TokenIndex] {
    let result = Buffer.Buffer<TokenIndex>(0);
    label l for (request in requests.vals()) {
      if (Ext.TokenIdentifier.isPrincipal(request.token, Principal.fromActor(this)) == false) {
        continue l;
      };
      let token = Ext.TokenIdentifier.getIndex(request.token);
      let owner = Ext.AccountIdentifier.fromPrincipal(msg.caller, request.subaccount);
      switch (_registry.get(token)) {
        case (?token_owner) {
          if (Ext.AccountIdentifier.equal(owner, token_owner) == false) {
            continue l;
          };
          _allowances.put(token, request.spender);
          result.add(token);
        };
        case (_) {};
      };
    };
    return result.toArray();
  };

  public query func tokens(aid : AccountIdentifier) : async Result.Result<[TokenIndex], CommonError> {
    let result = Buffer.Buffer<TokenIndex>(0);
    for ((tokenIndex, accountIdentifier) in _registry.entries()) {
      if (aid == accountIdentifier) {
        result.add(tokenIndex);
      };
    };
    if (result.size() > 0) {
      return #ok(result.toArray());
    };
    return #err(#Other("No tokens"));
  };


  type Time = Int;
  type Listing = {
    locked : ?Time;
    seller : Principal;
    price : Nat64;
  };
  //for dab
  public query func tokens_ext(aid : AccountIdentifier) : async Result.Result<[(TokenIndex, ?Listing, ?Blob)], CommonError> {
    let result = Buffer.Buffer<(TokenIndex, ?Listing, ?Blob)>(0);
    for ((tokenIndex, accountIdentifier) in _registry.entries()) {
      if (aid == accountIdentifier) {
        let md : ?Blob = switch (_tokenMetadata.get(tokenIndex)) {
          case (?md) {
            switch (md) {
              case (#fungible _) null;
              case (#nonfungible nmd) nmd.metadata;
            };
          };
          case _ {
            null;
          };
        };
        result.add(tokenIndex, null, md);
      };
    };
    if (result.size() > 0) {
      return #ok(result.toArray());
    };
    return #err(#Other("No tokens"));
  };

  let NOT_FOUND : HttpResponse = {
    status_code = 404;
    headers = [];
    body = Blob.fromArray([]);
  };
  let BAD_REQUEST : HttpResponse = {
    status_code = 400;
    headers = [];
    body = Blob.fromArray([]);
  };

  type HttpRequest = Http.Request;
  type HttpResponse = Http.Response;
  func _getUrl(md : Blob) : ?Text {
    let json = switch (Text.decodeUtf8(md)) {
      case (?text) {
        text;
      };
      case _ {
        return null;
      };
    };
    let p = Json.Parser();
    switch (p.parse(json)) {
      case (? #Object(v)) {
        switch (v.get("url")) {
          case (? #String(url)) {
            return ?url;
          };
          case _ {
            return null;
          };
        };
      };
      case _ {
        return null;
      };
    };
  };

  func _getThumb(md : Blob) : ?Text {
    let json = switch (Text.decodeUtf8(md)) {
      case (?text) {
        text;
      };
      case _ {
        return null;
      };
    };
    let p = Json.Parser();
    switch (p.parse(json)) {
      case (? #Object(v)) {
        switch (v.get("thumb")) {
          case (? #String(url)) {
            return ?url;
          };
          case _ {
            return null;
          };
        };
      };
      case _ {
        return null;
      };
    };
  };

  func _getBody(md : Blob) : ?Blob {
    let json = switch (Text.decodeUtf8(md)) {
      case (?text) {
        text;
      };
      case _ {
        return null;
      };
    };
    let p = Json.Parser();
    switch (p.parse(json)) {
      case (? #Object(v)) {
        switch (v.get("mimeType"), v.get("url")) {
          case (? #String(mimeType), ? #String(url)) {
            if (mimeType == "video") {
              let PREFIX = "<body oncontextmenu=self.event.returnValue=false><video src='";
              let POSTFIX = "' autoPlay loop controls controlslist='nodownload' style='width: 100%;height: 100%;'></video></body>";
              let padd = Blob.toArray(Text.encodeUtf8(PREFIX));
              let metaArr = Blob.toArray(Text.encodeUtf8(url));
              let suff = Blob.toArray(Text.encodeUtf8(POSTFIX));
              return ?Blob.fromArray(Array.append(Array.append(padd, metaArr), suff));
            } else if (mimeType == "3dmodel") {
              let environmentImageThree : Text = switch (v.get("environmentImageThree")) {
                case (? #String(environmentImageThree)) {
                  environmentImageThree;
                };
                case _ {
                  ""
                };
              };
              let PREFIX = "<html><head><script src='https://cdn.babylonjs.com/babylon.js'></script><script src='https://cdn.babylonjs.com/loaders/babylonjs.loaders.min.js'></script></head><body><canvas id='renderCanvas'style='width: 100%; height: 100%;'></canvas><div id='loadingScreen'style='position: absolute; top: 0; display: flex; align-items: center; justify-content: center;width: 100%; height: 100%;'><img src='https://yumi-frontend-assets.s3.ap-east-1.amazonaws.com/yumi/loading-gif.gif'style='width: 125px'/></div><script>var loadingScreenDiv=window.document.getElementById('loadingScreen');var canvas=document.getElementById('renderCanvas');var engine=new BABYLON.Engine(canvas,true,{},true);var scene=new BABYLON.Scene(engine);BABYLON.SceneLoader.ShowLoadingScreen=false;scene.clearColor=new BABYLON.Color3(1,1,1);var env=new BABYLON.HDRCubeTexture('" # environmentImageThree # "',scene,128);BABYLON.SceneLoader.Append('";
              let POSTFIX = "','',scene,function(scene){scene.createDefaultCameraOrLight(true,true,true);new BABYLON.GlowLayer('glow',scene);scene.environmentTexture=env;var loading=document.getElementById('loadingScreen');loading.style.display='none'},undefined,undefined,'.glb');engine.runRenderLoop(function(){if(scene&&scene.activeCamera){scene.render()}});window.addEventListener('resize',function(){engine.resize()});</script></body></html>";
              let padd = Blob.toArray(Text.encodeUtf8(PREFIX));
              let metaArr = Blob.toArray(Text.encodeUtf8(url));
              let suff = Blob.toArray(Text.encodeUtf8(POSTFIX));
              return ?Blob.fromArray(Array.append(Array.append(padd, metaArr), suff));
            } else if (mimeType == "image") {
              let padd = Blob.toArray(Text.encodeUtf8("<meta charset='UTF-8'><meta name='viewport' content='width=device-width, minimum-scale=0.1'><body style='margin: auto; height: 100%'><img style='display:block; -webkit-user-select: none;margin: auto;cursor: zoom-in;background-color: hsl(0, 0%, 90%);transition: background-color 300ms; height: 100%;' src='"));
              let suff = Blob.toArray(Text.encodeUtf8("'></img></body>"));
              let metaArr = Blob.toArray(Text.encodeUtf8(url));
              return ?Blob.fromArray(Array.append(Array.append(padd, metaArr), suff));
            } else {
              let padd = Blob.toArray(Text.encodeUtf8("<meta charset='UTF-8'><meta name='viewport' content='width=device-width, minimum-scale=0.1'><body style='margin: auto; height: 100%'><img style='display:block; -webkit-user-select: none;margin: auto;cursor: zoom-in;background-color: hsl(0, 0%, 90%);transition: background-color 300ms; height: 100%;' src='"));
              let suff = Blob.toArray(Text.encodeUtf8("'></img></body>"));
              let metaArr = Blob.toArray(Text.encodeUtf8(url));
              return ?Blob.fromArray(Array.append(Array.append(padd, metaArr), suff));
            };
          };
          case (null, ? #String(url)) {
            let padd = Blob.toArray(Text.encodeUtf8("<meta charset='UTF-8'><meta name='viewport' content='width=device-width, minimum-scale=0.1'><body style='margin: auto; height: 100%'><img style='display:block; -webkit-user-select: none;margin: auto;cursor: zoom-in;background-color: hsl(0, 0%, 90%);transition: background-color 300ms; height: 100%;' src='"));
            let suff = Blob.toArray(Text.encodeUtf8("'></img></body>"));
            let metaArr = Blob.toArray(Text.encodeUtf8(url));
            return ?Blob.fromArray(Array.append(Array.append(padd, metaArr), suff));
          };
          case _ {
            return null;
          };
        };
      };
      case _ {
        return null;
      };
    };
  };

  public query func http_request(request : HttpRequest) : async HttpResponse {
    switch (_getParam(request.url, "tokenid")) {
      case (?tokenIdentifier) {
        if (Ext.TokenIdentifier.isPrincipal(tokenIdentifier, Principal.fromActor(this)) == false) {
          return BAD_REQUEST;
        };
        let tokenIndex = Ext.TokenIdentifier.getIndex(tokenIdentifier);
        let md : Blob = switch (_tokenMetadata.get(tokenIndex)) {
          case (?md) {
            switch (md) {
              case (#fungible _) { return BAD_REQUEST };
              case (#nonfungible nmd) {
                switch (nmd.metadata) {
                  case (?blob) {
                    blob;
                  };
                  case _ {
                    return NOT_FOUND;
                  };
                };
              };
            };
          };
          case _ {
            return NOT_FOUND;
          };
        };
        switch (_getParam(request.url, "type")) {
          case (?t) {
            if (t == "thumbnail") {
              switch (_getThumb(md)) {
                case (?url) {
                  let padd = Blob.toArray(Text.encodeUtf8("<meta charset='UTF-8'><meta name='viewport' content='width=device-width, minimum-scale=0.1'><body style='margin: auto; height: 100%'><img style='display:block; -webkit-user-select: none;margin: auto;cursor: zoom-in;background-color: hsl(0, 0%, 90%);transition: background-color 300ms; height: 100%;' src='"));
                  let metaArr = Blob.toArray(Text.encodeUtf8(url));
                  let metaBlob = Text.encodeUtf8(url);
                  let suff = Blob.toArray(Text.encodeUtf8("'></img></body>"));
                  let meta = Blob.fromArray(Array.append(Array.append(padd, metaArr), suff));
                  return {
                    status_code = 200;
                    headers = [("content-type", "text/html")];
                    body = meta //when minted, its passed as svg
                    //body = Blob.toArray(Text.encodeUtf8(SVG.make(Traits.getBg(ids[0]), Traits.getPot(ids[1]), Traits.getStem(ids[2]), Traits.getPetal(ids[3]))));
                  };
                };
                case _ {
                  switch (_getBody(md)) {
                    case (?body) {
                      return {
                        status_code = 200;
                        headers = [("content-type", "text/html")];
                        body = body //when minted, its passed as svg
                        //body = Blob.toArray(Text.encodeUtf8(SVG.make(Traits.getBg(ids[0]), Traits.getPot(ids[1]), Traits.getStem(ids[2]), Traits.getPetal(ids[3]))));
                      };
                    };
                    case _ {
                      return NOT_FOUND;
                    };
                  };
                };
              };
            } else {
              return BAD_REQUEST;
            };
          };
          case _ {
            switch (_getBody(md)) {
              case (?body) {
                return {
                  status_code = 200;
                  headers = [("content-type", "text/html")];
                  body = body //when minted, its passed as svg
                  //body = Blob.toArray(Text.encodeUtf8(SVG.make(Traits.getBg(ids[0]), Traits.getPot(ids[1]), Traits.getStem(ids[2]), Traits.getPetal(ids[3]))));
                };
              };
              case _ {
                return NOT_FOUND;
              };
            };
          };
        };
      };
      case _ {
        return NOT_FOUND;
      };
    };
  };

  func _getTokenData(tokenid : ?Text) : ?Nat32 {
    switch (tokenid) {
      case (?token) {
        if (Ext.TokenIdentifier.isPrincipal(token, Principal.fromActor(this)) == false) {
          return null;
        };
        let tokenind : TokenIndex = Ext.TokenIdentifier.getIndex(token);
        let toret : Nat32 = tokenind + 1;
        var toretop : ?Nat32 = ?toret;
        return toretop;
      };
      case (_) {
        return null;
      };
    };
  };
  func _getParam(url : Text, param : Text) : ?Text {
    var _s : Text = url;
    Iter.iterate<Text>(
      Text.split(_s, #text("/")),
      func(x, _i) {
        _s := x;
      },
    );
    Iter.iterate<Text>(
      Text.split(_s, #text("?")),
      func(x, _i) {
        if (_i == 1) _s := x;
      },
    );
    var t : ?Text = null;
    var found : Bool = false;
    Iter.iterate<Text>(
      Text.split(_s, #text("&")),
      func(x, _i) {
        if (not found) {
          Iter.iterate<Text>(
            Text.split(x, #text("=")),
            func(y, _ii) {
              if (_ii == 0) {
                if (Text.equal(y, param)) found := true;
              } else if (found == true) t := ?y;
            },
          );
        };
      },
    );
    return t;
  };
  private let prefix : [Nat8] = [10, 116, 105, 100]; // \x0A "tid"
  private func encode(canisterId : Principal, tokenIndex : TokenIndex) : Text {
    let rawTokenId = Array.flatten<Nat8>([
      prefix,
      Blob.toArray(AviatePrincipal.toBlob(canisterId)),
      Binary.BigEndian.fromNat32(tokenIndex),
    ]);

    AviatePrincipal.toText(AviatePrincipal.fromBlob(Blob.fromArray(rawTokenId)));
  };

  private func _tokenIndexHash(tokenIndex : TokenIndex) : Hash.Hash {
    tokenIndex;
  };

  private stable var _rarityScoresState : [(TokenIndex, Float)] = [];
  private var _rarityScores : HashMap<TokenIndex, Float> = HashMap.fromIter(_rarityScoresState.vals(), 0, Ext.Core.TokenIndex.equal, Ext.Core.TokenIndex.hash);

  private stable var _rarityScoresStateInt : [(TokenIndex, Int64)] = [];
  private var _rarityScoresInt : HashMap<TokenIndex, Int64> = HashMap.fromIter(_rarityScoresStateInt.vals(), 0, Ext.Core.TokenIndex.equal, Ext.Core.TokenIndex.hash);

  private stable var _nftRarityPropertyScoreState : [(TokenIndex, [(Property, Int64)])] = [];
  private var _nftRarityPropertyScore : HashMap<TokenIndex, [(Property, Int64)]> = HashMap.fromIter(_nftRarityPropertyScoreState.vals(), 0, Ext.Core.TokenIndex.equal, Ext.Core.TokenIndex.hash);

  type TokenRarityScore = {
    tokenId : TokenIndex;
    score : Score;
  };

  private func _setScoreOfTokenId(raritydecimal : Int64) : () {
    // assert(msg.caller == Principal.fromText("6cwki-y67rz-mdivc-qqrf3-hqnz4-4vzml-ucxo5-mbuwp-ouak4-siv52-mqe"));
    let _propertiesArr = Iter.toArray(_properties.entries());
    _rarityScores := HashMap.HashMap<TokenIndex, Score>(0, Ext.Core.TokenIndex.equal, Ext.Core.TokenIndex.hash);

    _nftRarityPropertyScore := HashMap.HashMap<TokenIndex, [(Property, Int64)]>(0, Ext.Core.TokenIndex.equal, Ext.Core.TokenIndex.hash);

    _rarityScoresInt := HashMap.HashMap<TokenIndex, Int64>(0, Ext.Core.TokenIndex.equal, Ext.Core.TokenIndex.hash);

    for ((property, tokenIndexs) in _propertiesArr.vals()) {
      for (tokenIndex in tokenIndexs.vals()) {
        switch (_rarityScoresInt.get(tokenIndex)) {
          case (?socre) {
            var score_temp = Float.div(Float.fromInt(tokenIndexs.size()), Float.fromInt(_supply));
            score_temp := -Float.div(Float.log(score_temp), Float.log(2));
            var score_temp_int64 : Int64 = Float.toInt64(Float.mul(score_temp, Float.pow(10.0, Float.fromInt64(raritydecimal))));
            var propertyTemp = [(property, score_temp_int64)];
            switch (_nftRarityPropertyScore.get(tokenIndex)) {
              case (?propertynft) {
                var propertynft_new = Array.append(propertynft, propertyTemp);
                _nftRarityPropertyScore.put(tokenIndex, propertynft_new);
              };
              case _ {};
            };
            let scoreNew : Int64 = socre + score_temp_int64;
            _rarityScoresInt.put(tokenIndex, scoreNew);
          };
          case _ {
            var score_temp = Float.div(Float.fromInt(tokenIndexs.size()), Float.fromInt(_supply));
            score_temp := -Float.div(Float.log(score_temp), Float.log(2));
            var score_temp_int64 : Int64 = Float.toInt64(Float.mul(score_temp, Float.pow(10.0, Float.fromInt64(raritydecimal))));
            var propertyTemp = [(property, score_temp_int64)];
            _nftRarityPropertyScore.put(tokenIndex, propertyTemp);

            _rarityScoresInt.put(tokenIndex, score_temp_int64);
          };
        };
      };
    };

    for ((tokenIndex, intScore) in _rarityScoresInt.entries()) {
      var score : Float = Float.div(Float.fromInt64(intScore), Float.pow(10.0, Float.fromInt64(raritydecimal)));
      _rarityScores.put(tokenIndex, score);
    };

  };

  public query func lookPropertyScoreByTokenId() : async [(TokenIndex, [(Property, Int64)])] {
    Iter.toArray(_nftRarityPropertyScore.entries());
  };

  public shared (msg) func setScoreOfTokenId(raritydecimal : Int64) : async () {
    assert (msg.caller == Principal.fromText("6cwki-y67rz-mdivc-qqrf3-hqnz4-4vzml-ucxo5-mbuwp-ouak4-siv52-mqe"));
    _setScoreOfTokenId(raritydecimal);
  };

  public query func getScore() : async [(TokenIndex, Float)] {
    Iter.toArray(_rarityScores.entries());
  };
};
