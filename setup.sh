#!/bin/bash -eE

RNODE_CONSOLE_SERVER_PORT="3031"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=env.sh
. "${SCRIPT_DIR}/env.sh"

HOSTNAME=$(hostname -f)
TMP_DIR=/tmp/$(basename "$0" .sh)_$$
rm -rf "${TMP_DIR}"
mkdir -p "${TMP_DIR}"

echo "INFO: setup Free TON node dependencies..."

sudo apt update && sudo apt install -y \
    librdkafka1 \
    build-essential \
    cmake \
    cron \
    git \
    gdb \
    gpg \
    jq \
    tar \
    vim \
    tcpdump \
    netcat \
    python3 \
    python3-pip \
    wget

echo "INFO: setup Free TON node dependencies... DONE"

echo "INFO: setup Free TON node..."

echo
read -p "This script will REMOVE your previous ton-node installation. Are you sure? (Y/N)" -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
fi

SETUP_USER="$(id --user)"
SETUP_GROUP="$(id --group)"

BIN_DIR="${SRC_TOP_DIR}/bin"
TOOLS_DIR="${SRC_TOP_DIR}/tools"

sudo rm -rf "${TON_WORK_DIR}"

sudo mkdir -p "${TON_WORK_DIR}"
sudo chown "${SETUP_USER}:${SETUP_GROUP}" "${TON_WORK_DIR}"

mkdir "${TON_WORK_DIR}/logs"

cp -r "${SCRIPT_DIR}/configs" "${TON_WORK_DIR}"

mkdir -p "${HOME}/keys"
ln -s "${HOME}/keys" "${TON_WORK_DIR}/configs/keys"

sed -i "s@/ton-node@${TON_WORK_DIR}@g" "${TON_WORK_DIR}/configs/log_cfg.yml"

"${TOOLS_DIR}/keygen" > "${TON_WORK_DIR}/configs/${HOSTNAME}_console_client_keys.json"
jq -c .public "${TON_WORK_DIR}/configs/${HOSTNAME}_console_client_keys.json" > "${TON_WORK_DIR}/configs/console_client_public.json"

jq ".control_server_port = ${RNODE_CONSOLE_SERVER_PORT}" "${TON_WORK_DIR}/configs/default_config.json" > "${TMP_DIR}/default_config.json.tmp"
cp "${TMP_DIR}/default_config.json.tmp" "${TON_WORK_DIR}/configs/default_config.json"
cp "${SRC_TOP_DIR}/ton-labs-contracts/solidity/safemultisig/SafeMultisigWallet.abi.json" "${TON_WORK_DIR}/configs/"

# Generate initial config.json

cd "${BIN_DIR}" && "${BIN_DIR}"/ton_node --configs "${TON_WORK_DIR}/configs" --ckey "$(cat "${TON_WORK_DIR}/configs/console_client_public.json")" &

sleep 10

if [ ! -f "${TON_WORK_DIR}/configs/config.json" ]; then
	echo "ERROR: ${TON_WORK_DIR}/configs/config.json does not exist"
    exit 1
fi

if [ ! -f "${TON_WORK_DIR}/configs/console_config.json" ]; then
        echo "ERROR: ${TON_WORK_DIR}/configs/console_config.json does not exist"
    exit 1
fi

jq ".client_key = $(jq .private "${TON_WORK_DIR}/configs/${HOSTNAME}_console_client_keys.json")" "${TON_WORK_DIR}/configs/console_config.json" > "${TMP_DIR}/console_config.json.tmp"
jq ".config = $(cat "${TMP_DIR}/console_config.json.tmp")" "${TON_WORK_DIR}/configs/console_template.json" > "${TON_WORK_DIR}/configs/console.json"
rm -f "${TON_WORK_DIR}/configs/console_config.json"

curl -sS "https://raw.githubusercontent.com/tonlabs/rustnet.ton.dev/main/configs/ton-global.config.json" -o "${TON_WORK_DIR}/configs/ton-global.config.json"

rm -rf "${TMP_DIR}"
