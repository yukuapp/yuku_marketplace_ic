module {
    public type Result<T, E> = {
        #Ok : T;
        #Err : E;
    };

    public type TransferResult = Result<BlockIndex, TransferError>;

    // Amount of ICP tokens, measured in 10^-8 of a token.
    public type ICP = {
        e8s : Nat64;
    };

    // Number of nanoseconds from the UNIX epoch (00:00:00 UTC, Jan 1, 1970).
    public type Timestamp = {
        timestamp_nanos : Nat64;
    };

    // AccountIdentifier is a 32-byte array.
    // The first 4 bytes is big-endian encoding of a CRC32 checksum of the last 28 bytes.
    public type AccountIdentifier = Blob;

    // Subaccount is an arbitrary 32-byte byte array.
    // Ledger uses subaccounts to compute the source address, which enables one
    // principal to control multiple ledger accounts.
    public type SubAccount = Blob;

    // Sequence number of a block produced by the ledger.
    public type BlockIndex = Nat64;

    // An arbitrary number associated with a transaction.
    // The caller can set it in a `transfer` call as a correlation identifier.
    public type Memo = Nat64;

    // Arguments for the `transfer` call.
    public type TransferArgs = {
        // Transaction memo.
        // See comments for the `Memo` type.
        memo : Memo;
        // The amount that the caller wants to transfer to the destination address.
        amount : ICP;
        // The amount that the caller pays for the transaction.
        // Must be 10000 e8s.
        fee : ICP;
        // The subaccount from which the caller wants to transfer funds.
        // If null, the ledger uses the default (all zeros) subaccount to compute the source address.
        // See comments for the `SubAccount` type.
        from_subaccount : ?SubAccount;
        // The destination account.
        // If the transfer is successful, the balance of this account increases by `amount`.
        to : AccountIdentifier;
        // The point in time when the caller created this request.
        // If null, the ledger uses current IC time as the timestamp.
        created_at_time : ?Timestamp;
    };

    public type TransferError = {
        // The fee that the caller specified in the transfer request was not the one that the ledger expects.
        // The caller can change the transfer fee to the `expected_fee` and retry the request.
        #BadFee : { expected_fee : ICP };
        // The account specified by the caller doesn't have enough funds.
        #InsufficientFunds : { balance : ICP };
        // The request is too old.
        // The ledger only accepts requests created within a 24 hours window.
        // This is a non-recoverable error.
        #TxTooOld : { allowed_window_nanos : Nat64 };
        // The caller specified `created_at_time` that is too far in future.
        // The caller can retry the request later.
        #TxCreatedInFuture;
        // The ledger has already executed the request.
        // `duplicate_of` field is equal to the index of the block containing the original transaction.
        #TxDuplicate : { duplicate_of : BlockIndex };
    };

    // Arguments for the `account_balance` call.
    public type AccountBalanceArgs = {
        account : AccountIdentifier;
    };

    public type GetBlocksArgs = { start : Nat64; length : Nat64 };

    public type QueryBlocksResponse = {
        certificate : ?[Nat8];
        blocks : [CandidBlock];
        chain_length : Nat64;
        first_block_index : Nat64;
        archived_blocks : [ArchivedBlocksRange];
    };

    public type CandidBlock = {
        transaction : CandidTransaction;
        timestamp : TimeStamp;
        parent_hash : ?[Nat8];
    };

    public type ArchivedBlocksRange = {
        callback : shared query GetBlocksArgs -> async {
            #Ok : BlockRange;
            #Err : GetBlocksError;
        };
        start : Nat64;
        length : Nat64;
    };

    public type CandidTransaction = {
        memo : Nat64;
        icrc1_memo : ?[Nat8];
        operation : ?CandidOperation;
        created_at_time : TimeStamp;
    };

    public type TimeStamp = { timestamp_nanos : Nat64 };
    public type BlockRange = { blocks : [CandidBlock] };
    public type GetBlocksError = {
        #BadFirstBlockIndex : {
            requested_index : Nat64;
            first_valid_index : Nat64;
        };
        #Other : { error_message : Text; error_code : Nat64 };
    };
    public type CandidOperation = {
        #Approve : {
            fee : Tokens;
            from : [Nat8];
            allowance_e8s : Int;
            expires_at : ?TimeStamp;
            spender : [Nat8];
        };
        #Burn : { from : [Nat8]; amount : Tokens };
        #Mint : { to : [Nat8]; amount : Tokens };
        #Transfer : {
            to : [Nat8];
            fee : Tokens;
            from : [Nat8];
            amount : Tokens;
        };
        #TransferFrom : {
            to : [Nat8];
            fee : Tokens;
            from : [Nat8];
            amount : Tokens;
            spender : [Nat8];
        };
    };
    public type Tokens = { e8s : Nat64 };
    public type Self = actor {
        query_blocks : shared query GetBlocksArgs -> async QueryBlocksResponse;
        transfer : TransferArgs -> async TransferResult;
        account_balance : AccountBalanceArgs -> async ICP;
    };

    public let ID = "irzpe-yqaaa-aaaah-abhfa-cai";
};
