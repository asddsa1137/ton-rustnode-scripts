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
COMPRESSION="true"

BIN_DIR="${SRC_TOP_DIR}/bin"
TOOLS_DIR="${SRC_TOP_DIR}/tools"

export RUSTFLAGS="-C target-cpu=native"
RUST_VERSTION="1.54.0"

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
    librdkafka-dev \
    libzstd-dev

if command -v rustc &> /dev/null ; then
  INSTALLED_RUST_VERSION=$(rustc --version |awk '{print $2}')
fi


if [ "${INSTALLED_RUST_VERSION}" !=  "${RUST_VERSTION}" ]; then
  cp $SCRIPT_DIR/rust_install.sh $TMP_DIR
  cd $TMP_DIR && sudo ./rust_install.sh "${RUST_VERSTION}"
fi

rm -rf "${NODE_BUILD_DIR}"

mkdir -p "${NODE_BUILD_DIR}"
mkdir -p "${BIN_DIR}" "${TOOLS_DIR}"

echo "INFO: build a node..."
echo "${NODE_BUILD_DIR}"

cd "${NODE_BUILD_DIR}" && git clone --recursive "${TON_NODE_GITHUB_REPO}" ton-node
cd "${NODE_BUILD_DIR}/ton-node" && git checkout "${TON_NODE_GITHUB_COMMIT_ID}"

# patch node with black magic
sed -i '0,/Ok(Stats {stats})/s/Ok(Stats {stats})/PLACEHOLDER\n            Ok(Stats {stats})/' "${NODE_BUILD_DIR}/ton-node/src/network/control.rs"
sed -i "/PLACEHOLDER/r $SCRIPT_DIR/patch_control.rs" "${NODE_BUILD_DIR}/ton-node/src/network/control.rs"
sed -i "/PLACEHOLDER/d" "${NODE_BUILD_DIR}/ton-node/src/network/control.rs"

cargo update
if [ "${COMPRESSION}" = "true" ]; then
    export ZSTD_LIB_DIR="/usr/lib/x86_64-linux-gnu"
    cargo build --release --features "compression"
else
    cargo build
fi

if [ -f "${NODE_BUILD_DIR}/ton-node/target/release/ton_node" ]; then
    mv "${BIN_DIR}/ton_node" "${TMP_DIR}/" &> /dev/null || true
    cp "${NODE_BUILD_DIR}/ton-node/target/release/ton_node" "${BIN_DIR}/"
fi

echo "INFO: build a node... DONE"

echo "INFO: build utils (ton-labs-node-tools)..."

cd "${NODE_BUILD_DIR}/" && git clone --recursive "${TON_NODE_TOOLS_GITHUB_REPO}"
cd "${NODE_BUILD_DIR}/ton-labs-node-tools" && git checkout "${TON_NODE_TOOLS_GITHUB_COMMIT_ID}"

# Fix for rust 1.54
sed -i 's/shell-words = ""/shell-words = "1.0.0"/' "${NODE_BUILD_DIR}/ton-labs-node-tools/Cargo.toml"

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

cd "${NODE_BUILD_DIR}/" && git clone --recursive "${TVM_LINKER_REPO}"
cd "${NODE_BUILD_DIR}/TVM-linker/tvm_linker" && git checkout "${TVM_LINKER_COMMIT_ID}"

cargo update
cargo build --release

if [ -f "${NODE_BUILD_DIR}/TVM-linker/tvm_linker/target/release/tvm_linker" ]; then
    mv "${TOOLS_DIR}/tvm_linker" "${TMP_DIR}/" &> /dev/null || true
    cp "${NODE_BUILD_DIR}/TVM-linker/tvm_linker/target/release/tvm_linker" "${TOOLS_DIR}/"
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
