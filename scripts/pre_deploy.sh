#!/usr/bin/env bash
NETWORK=$1
PWD=$(pwd)
if [ $NETWORK == "local" ]; then
    export CANISTER_IDS_JSON="$(pwd)/.dfx/local/canister_ids.json";
else
    export CANISTER_IDS_JSON="'$(pwd)'/canister_ids.json";
fi

export YUKU=$(jq '.yuku.'$NETWORK'' $CANISTER_IDS_JSON)
export LAUNCHPAD_CANISTERID=$(jq '.launchpad.'$NETWORK'' $CANISTER_IDS_JSON)
export OWNER_PRINCIPAL=$(dfx identity get-principal)
export OWNER_PRINCIPAL=$(dfx identity get-principal)

