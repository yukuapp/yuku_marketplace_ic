# !/usr/bin/env bash
dfx stop
dfx start --clean --background
dfx canister create --all
source ./scripts/pre_deploy.sh local
source ./scripts/post_deploy.sh local