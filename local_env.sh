#!/bin/bash -eE

export RUST_NET_ENABLE=yes
export VALIDATOR_NAME="$HOSTNAME"
export UTILS_DIR="${SRC_TOP_DIR}/tools"
export PATH="${UTILS_DIR}:$PATH"
export TON_WORK_DIR="/var/ton-node"
export SDK_URL="https://main.ton.dev"
export MSIG_ENABLE=yes
