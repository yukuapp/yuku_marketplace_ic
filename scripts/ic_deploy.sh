#!/usr/bin/env bash
dfx canister create --network ic  --all
source ./scripts/pre_deploy.sh ic
source ./scripts/post_deploy.sh ic