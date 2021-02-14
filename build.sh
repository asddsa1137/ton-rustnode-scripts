#!/bin/bash -eE

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=env.sh
. "${SCRIPT_DIR}/env.sh"

TMP_DIR=/tmp/$(basename "$0" .sh)_$$
rm -rf "${TMP_DIR}"
mkdir -p "${TMP_DIR}"

NODE_BUILD_DIR="${SRC_TOP_DIR}/build"
TOOLS_BUILD_DIR="${SRC_TOP_DIR}/build/ton-labs-node-tools"
TONOS_CLI_BUILD_DIR="${SRC_TOP_DIR}/build/tonos-cli"

BIN_DIR="${SRC_TOP_DIR}/bin"
TOOLS_DIR="${SRC_TOP_DIR}/tools"

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
cd $TMP_DIR && sudo ./rust_install.sh 1.50.0

rm -rf "${NODE_BUILD_DIR}"

mkdir -p "${NODE_BUILD_DIR}"
mkdir -p "${BIN_DIR}" "${TOOLS_DIR}"

echo "INFO: build a node..."
echo "${NODE_BUILD_DIR}"

cd "${NODE_BUILD_DIR}" && git clone --recursive "${TON_NODE_GITHUB_REPO}" ton-node
cd "${NODE_BUILD_DIR}/ton-node" && git checkout "${TON_NODE_GITHUB_COMMIT_ID}"

cargo update
cargo build --release

if [ -f "${NODE_BUILD_DIR}/ton-node/target/release/ton_node" ]; then
    mv "${BIN_DIR}/ton_node" "${TMP_DIR}/" &> /dev/null || true
    cp "${NODE_BUILD_DIR}/ton-node/target/release/ton_node" "${BIN_DIR}/"
fi

echo "INFO: build a node... DONE"

echo "INFO: build utils (ton-labs-node-tools)..."

cd "${NODE_BUILD_DIR}/" && git clone --recursive "${TON_NODE_TOOLS_GITHUB_REPO}"
cd "${NODE_BUILD_DIR}/ton-labs-node-tools" && git checkout "${TON_NODE_TOOLS_GITHUB_COMMIT_ID}"

cargo update
cargo build --release

if [ -f "${NODE_BUILD_DIR}/ton-labs-node-tools/target/release/console" ]; then
    mv "${TOOLS_DIR}/console" "${TMP_DIR}/" &> /dev/null || true
    cp "${NODE_BUILD_DIR}/ton-labs-node-tools/target/release/console" "${TOOLS_DIR}/"
fi
if [ -f "${NODE_BUILD_DIR}/ton-labs-node-tools/target/release/keygen" ]; then
    mv "${TOOLS_DIR}/keygen" "${TMP_DIR}/" &> /dev/null || true
    cp "${NODE_BUILD_DIR}/ton-labs-node-tools/target/release/keygen" "${TOOLS_DIR}/"
fi

echo "INFO: build utils (ton-labs-node-tools)... DONE"

echo "INFO: build utils (tonos-cli)..."

cd "${NODE_BUILD_DIR}" && git clone --recursive "${TONOS_CLI_GITHUB_REPO}"
cd "${NODE_BUILD_DIR}/tonos-cli" && git checkout "${TONOS_CLI_GITHUB_COMMIT_ID}"

cargo update
cargo build --release

if [ -f "${NODE_BUILD_DIR}/tonos-cli/target/release/tonos-cli" ]; then
    mv "${TOOLS_DIR}/tonos-cli" "${TMP_DIR}" &> /dev/null || true
    cp "${NODE_BUILD_DIR}/tonos-cli/target/release/tonos-cli" "${TOOLS_DIR}/"
fi

echo "INFO: build utils (tonos-cli)... DONE"

echo "INFO: pull TON Labs contracts..."
rm -rf "${SRC_TOP_DIR}/ton-labs-contracts"
git clone https://github.com/tonlabs/ton-labs-contracts.git "${SRC_TOP_DIR}/ton-labs-contracts"
echo "INFO: pull TON Labs contracts... DONE"
