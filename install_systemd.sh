#!/bin/bash -eE

TON_WORK_DIR="/var/ton-node"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=env.sh
. "${SCRIPT_DIR}/env.sh"

HOSTNAME=$(hostname -f)
TMP_DIR=/tmp/$(basename "$0" .sh)_$$
rm -rf "${TMP_DIR}"
mkdir -p "${TMP_DIR}"

SETUP_USER="$(id -u -n)"
SETUP_GROUP="$(id -g -n)"

cp "${SCRIPT_DIR}/systemd/ton-rust-node.service" "${TMP_DIR}/ton-rust-node2.service"
sed -i "s@ROOT@${TON_WORK_DIR}@" "${TMP_DIR}/ton-rust-node2.service"
sed -i "s@CONFIGS@${TON_WORK_DIR}/configs@" "${TMP_DIR}/ton-rust-node2.service"
sed -i "s@LOG@${TON_WORK_DIR}/logs/node.log@" "${TMP_DIR}/ton-rust-node2.service"
sed -i "s@BIN@${SRC_TOP_DIR}/bin/ton_node@" "${TMP_DIR}/ton-rust-node2.service"
sed -i "s@USER@${SETUP_USER}@" "${TMP_DIR}/ton-rust-node2.service"
sed -i "s@GROUP@${SETUP_GROUP}@"  "${TMP_DIR}/ton-rust-node2.service"

cp "${SCRIPT_DIR}/systemd/ton-rust-node.env" "${TMP_DIR}/ton-rust-node2.env"
sed -i "s@CONFIGS_DIR@${TON_WORK_DIR}/configs@" "${TMP_DIR}/ton-rust-node2.env"

sudo cp "${TMP_DIR}/ton-rust-node2.service" "${TMP_DIR}/ton-rust-node2.env" "/etc/systemd/system"
sudo systemctl daemon-reload

rm -rf "${TMP_DIR}"
