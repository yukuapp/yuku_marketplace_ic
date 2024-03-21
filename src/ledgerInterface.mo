
import Ledger "ledger";
import Nat64 "mo:base/Nat64";
module {
    public func query_blocks(ledger_canister : Text,height : Nat64) : async  ?Ledger.CandidTransaction{
        let ledgerActor : Ledger.Self = actor (ledger_canister);
        let getBlockArgs = {
            start = height;
            length = Nat64.fromNat(1);
        };
        let blockReponse = await ledgerActor.query_blocks(getBlockArgs);
        if (blockReponse.blocks.size() == 1) {
            return ?blockReponse.blocks[0].transaction;
        };
        let archive = blockReponse.archived_blocks[0];
        let callbackResponse =  await archive.callback(getBlockArgs);
        switch(callbackResponse){
            case (#Ok(blockRange)){
                if(blockRange.blocks.size() == 1) {
                    return ?blockRange.blocks[0].transaction;
                }
            };
            case _ {};
        };
        return null;
    };
}