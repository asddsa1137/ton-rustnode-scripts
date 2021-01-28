#!/bin/bash -eE

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=env.sh
. "${SCRIPT_DIR}/env.sh"

TMP_DIR=/tmp/$(basename "$0" .sh)_$$
rm -rf "${TMP_DIR}"
mkdir -p "${TMP_DIR}"

NODE_BUILD_DIR="${SRC_TOP_DIR}/build"
TOOLS_BUILD_DIR="${SRC_TOP_DIR}/build/ton-node/ton-labs-node-tools"
TONOS_CLI_BUILD_DIR="${SRC_TOP_DIR}/build/tonos-cli"

sudo apt update && sudo apt install -y \
    gpg \
    tar \
    cmake \
    build-essential \
    pkg-config \
    libssl-dev \
    libtool \
    m4 \
    automake \
    clang \
    git \
    curl \
    gnupg2 \
    librdkafka-dev

cp $SCRIPT_DIR/rust_install.sh $TMP_DIR
cd $TMP_DIR && sudo ./rust_install.sh 1.45.2

rm -rf "${NODE_BUILD_DIR}"

mkdir -p "${NODE_BUILD_DIR}"

echo "INFO: build a node..."
echo "${NODE_BUILD_DIR}"

cd "${NODE_BUILD_DIR}" && git clone --recursive "${TON_NODE_GITHUB_REPO}" ton-node
cd "${NODE_BUILD_DIR}/ton-node" && git checkout "${TON_NODE_GITHUB_COMMIT_ID}"

cargo update
cargo build --release

echo "INFO: build a node... DONE"

echo "INFO: build utils (ton-labs-node-tools)..."

cd "${NODE_BUILD_DIR}/ton-node" && git clone --recursive "${TON_NODE_TOOLS_GITHUB_REPO}"
cd "${NODE_BUILD_DIR}/ton-node/ton-labs-node-tools" && git checkout "${TON_NODE_TOOLS_GITHUB_COMMIT_ID}"

cargo update
cargo build --release

echo "INFO: build utils (ton-labs-node-tools)... DONE"

echo "INFO: build utils (tonos-cli)..."

cd "${NODE_BUILD_DIR}" && git clone --recursive "${TONOS_CLI_GITHUB_REPO}"
cd "${NODE_BUILD_DIR}/tonos-cli" && git checkout "${TONOS_CLI_GITHUB_COMMIT_ID}"

cargo update
cargo build --release

echo "INFO: build utils (tonos-cli)... DONE"

echo "INFO: pull TON Labs contracts..."
git clone https://github.com/tonlabs/ton-labs-contracts.git "${NODE_BUILD_DIR}/ton-labs-contracts"
echo "INFO: pull TON Labs contracts... DONE"