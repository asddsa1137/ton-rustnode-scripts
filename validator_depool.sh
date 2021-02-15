#!/bin/bash -eE

set -o pipefail

if [ "$DEBUG" = "yes" ]; then
    set -x
fi

echo "INFO: $(basename "$0") BEGIN $(date +%s) / $(date)"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=env.sh
. "${SCRIPT_DIR}/env.sh"

TMP_DIR=/tmp/$(basename "$0" .sh)_$$
rm -rf "${TMP_DIR}"
mkdir -p "${TMP_DIR}"

CONTRACTS_DIR="${SRC_TOP_DIR}/ton-labs-contracts/solidity"
TON_NODE_ROOT="${TON_WORK_DIR}"
CONFIGS_DIR="${TON_NODE_ROOT}/configs"
KEYS_DIR="${CONFIGS_DIR}/keys"
WORK_DIR="${UTILS_DIR}"

MAX_FACTOR=${MAX_FACTOR:-3}
TONOS_CLI_SEND_ATTEMPTS="10"
ELECTOR_ADDR="-1:3333333333333333333333333333333333333333333333333333333333333333"
MSIG_ADDR_FILE="${KEYS_DIR}/${VALIDATOR_NAME}.addr"
DEPOOL_ADDR_FILE="${KEYS_DIR}/depool.addr"
HELPER_ADDR_FILE="${KEYS_DIR}/helper.addr"

if [ ! -f "${MSIG_ADDR_FILE}" ]; then
    echo "ERROR: ${MSIG_ADDR_FILE} does not exist"
    exit 1
fi
MSIG_ADDR=$(cat "${MSIG_ADDR_FILE}")

if [ ! -f "${DEPOOL_ADDR_FILE}" ]; then
    echo "ERROR: "${DEPOOL_ADDR_FILE}" does not exist"
    exit 1
fi
DEPOOL_ADDR=$(cat "${DEPOOL_ADDR_FILE}")

if [ -f "${HELPER_ADDR_FILE}" ]; then
    HELPER_ADDR=$(cat "${HELPER_ADDR_FILE}")
fi

echo "INFO: MSIG_ADDR = ${MSIG_ADDR}"
echo "INFO: DEPOOL_ADDR = ${DEPOOL_ADDR}"

ACTIVE_ELECTION_ID_HEX=$(${UTILS_DIR}/tonos-cli run ${ELECTOR_ADDR} active_election_id {} --abi ${CONFIGS_DIR}/Elector.abi.json 2>&1 | grep "value0" | awk '{print $2}' | tr -d '"')
if [ -z "${ACTIVE_ELECTION_ID_HEX}" ]; then
   	echo "ERROR: failed to get active elections ID"
        exit 1
fi
ACTIVE_ELECTION_ID=$(printf "%d" "${ACTIVE_ELECTION_ID_HEX}")
echo "INFO: ACTIVE_ELECTION_ID = ${ACTIVE_ELECTION_ID}"

if [ "${ACTIVE_ELECTION_ID}" = "0" ]; then
    date +"INFO: %F %T No current elections"
    echo "INFO: $(basename "$0") END $(date +%s) / $(date)"
    exit 0
fi

ELECTIONS_WORK_DIR="${KEYS_DIR}/elections/${ACTIVE_ELECTION_ID}"
mkdir -p "${ELECTIONS_WORK_DIR}"

echo "${ACTIVE_ELECTION_ID}" >"${ELECTIONS_WORK_DIR}/election-id"

if [ -f "${ELECTIONS_WORK_DIR}/stop-election" ]; then
    echo "INFO: $(basename "$0") END $(date +%s) / $(date)"
    exit 0
fi

if [ -f "${ELECTIONS_WORK_DIR}/active-election-id-submitted" ]; then
    ACTIVE_ELECTION_ID_SUBMITTED=$(cat "${ELECTIONS_WORK_DIR}/active-election-id-submitted")
    if [ "${ACTIVE_ELECTION_ID_SUBMITTED}" = "${ACTIVE_ELECTION_ID}" ]; then
        date +"INFO: %F %T Elections ${ACTIVE_ELECTION_ID} already submitted"
        echo "INFO: $(basename "$0") END $(date +%s) / $(date)"
        exit 0
    fi
fi

date +"INFO: %F %T Elections ${ACTIVE_ELECTION_ID}"

"${UTILS_DIR}/tonos-cli" depool --addr "${DEPOOL_ADDR}" events >"${ELECTIONS_WORK_DIR}/events.txt" 2>&1

set +eE
ACTIVE_ELECTION_ID_FROM_DEPOOL_EVENT=$(grep "^{" "${ELECTIONS_WORK_DIR}/events.txt" | grep electionId |
    jq ".electionId" | head -1 | tr -d '"' | xargs printf "%d\n")
echo "INFO: ACTIVE_ELECTION_ID_FROM_DEPOOL_EVENT = ${ACTIVE_ELECTION_ID_FROM_DEPOOL_EVENT}"

ACTIVE_ELECTION_ID_TIME_DIFF=$(($ACTIVE_ELECTION_ID - $ACTIVE_ELECTION_ID_FROM_DEPOOL_EVENT))
if [ $ACTIVE_ELECTION_ID_TIME_DIFF -lt 1000 ]; then
    PROXY_ADDR_FROM_DEPOOL_EVENT=$(grep "^{" "${ELECTIONS_WORK_DIR}/events.txt" | grep electionId |
        jq ".proxy" | head -1 | tr -d '"')
    echo "INFO: PROXY_ADDR_FROM_DEPOOL_EVENT = ${PROXY_ADDR_FROM_DEPOOL_EVENT}"
    if [ -z "${PROXY_ADDR_FROM_DEPOOL_EVENT}" ]; then
        echo "ERROR: unable to detect PROXY_ADDR_FROM_DEPOOL_EVENT"
        exit 1
    fi
else
    echo "INFO: ACTIVE_ELECTION_ID_FROM_DEPOOL_EVENT (${ACTIVE_ELECTION_ID_FROM_DEPOOL_EVENT}) does not match to ACTIVE_ELECTION_ID (${ACTIVE_ELECTION_ID})"
    if [ ! -z "${HELPER_ADDR}" ]; then
	echo "INFO: try to ticktock"
        for i in $(seq ${TONOS_CLI_SEND_ATTEMPTS}); do
            echo "INFO: tonos-cli sendTicktock attempt #${i}..."
            set -x
            if ! "${UTILS_DIR}/tonos-cli" call "${HELPER_ADDR}" sendTicktock \
                "{}" \
                --abi "${CONTRACTS_DIR}/depool/DePoolHelper.abi.json" \
                --sign "${KEYS_DIR}/helper.json"; then
                echo "INFO: tonos-cli submitTransaction attempt #${i}... FAIL"
            else
                echo "INFO: tonos-cli submitTransaction attempt #${i}... PASS"
                break
            fi
            set +x
        done
    fi
    exit 1
fi
set -eE

ELECTIONS_ARTEFACTS_CREATED="0"
if [ -f "${ELECTIONS_WORK_DIR}/election-artefacts-created" ] &&
    [ "${ACTIVE_ELECTION_ID_FROM_DEPOOL_EVENT}" = "$(cat "${ELECTIONS_WORK_DIR}/election-artefacts-created")" ]; then
    ELECTIONS_ARTEFACTS_CREATED="1"
fi

if [ "${ELECTIONS_ARTEFACTS_CREATED}" = "0" ]; then
   GLOBAL_CONFIG_15_RAW=$(${UTILS_DIR}/tonos-cli getconfig 15 2>&1)
   ELECTIONS_END_BEFORE=$(echo "$GLOBAL_CONFIG_15_RAW" | grep "elections_end_before" | awk '{print $2}' | tr -d ',')
   ELECTIONS_START_BEFORE=$(echo "$GLOBAL_CONFIG_15_RAW" | grep "elections_start_before" | awk '{print $2}' | tr -d ',')
   STAKE_HELD_FOR=$(echo "$GLOBAL_CONFIG_15_RAW" | grep "stake_held_for" | awk '{print $2}' | tr -d ',')
   VALIDATORS_ELECTED_FOR=$(echo "$GLOBAL_CONFIG_15_RAW" | grep "validators_elected_for" | awk '{print $2}' | tr -d ',')
   echo "INFO: ELECTIONS_START_BEFORE = ${ELECTIONS_START_BEFORE}"
   echo "INFO: ELECTIONS_END_BEFORE = ${ELECTIONS_END_BEFORE}"
   echo "INFO: STAKE_HELD_FOR = ${STAKE_HELD_FOR}"
   echo "INFO: VALIDATORS_ELECTED_FOR = ${VALIDATORS_ELECTED_FOR}"

   ELECTION_START="${ACTIVE_ELECTION_ID_FROM_DEPOOL_EVENT}"
   # TODO: duration may be reduced - to be checked
   ELECTION_STOP=$((ACTIVE_ELECTION_ID_FROM_DEPOOL_EVENT + 1000 + ELECTIONS_START_BEFORE + ELECTIONS_END_BEFORE + STAKE_HELD_FOR + VALIDATORS_ELECTED_FOR))

   jq ".wallet_id = \"${PROXY_ADDR_FROM_DEPOOL_EVENT}\"" ${CONFIGS_DIR}/console.json >"${TMP_DIR}/console.json"
   ${UTILS_DIR}/console -C ${TMP_DIR}/console.json -c "election-bid ${ELECTION_START} ${ELECTION_STOP}"
   mv validator-query.boc "${ELECTIONS_WORK_DIR}"

   echo "${ACTIVE_ELECTION_ID_FROM_DEPOOL_EVENT}" >"${ELECTIONS_WORK_DIR}/election-artefacts-created"

else
       echo "WARNING: election artefacts already created"
fi

if [ -f "${ELECTIONS_WORK_DIR}/validator-query.boc" ]; then
    VALIDATOR_QUERY_BOC=$(base64 --wrap=0 "${ELECTIONS_WORK_DIR}/validator-query.boc")
else
    echo "ERROR: ${ELECTIONS_WORK_DIR}/validator-query.boc does not exist"
    rm -f "${ELECTIONS_WORK_DIR}/election-artefacts-created"
    exit_and_clean 1 $LINENO
fi

if [ -z "${VALIDATOR_QUERY_BOC}" ]; then
    echo "ERROR: VALIDATOR_QUERY_BOC is empty"
    exit_and_clean 1 $LINENO
fi

for i in $(seq ${TONOS_CLI_SEND_ATTEMPTS}); do
    echo "INFO: tonos-cli submitTransaction attempt #${i}..."
    set -x
    if ! "${UTILS_DIR}/tonos-cli" call "${MSIG_ADDR}" submitTransaction \
        "{\"dest\":\"${DEPOOL_ADDR}\",\"value\":\"1000000000\",\"bounce\":true,\"allBalance\":false,\"payload\":\"${VALIDATOR_QUERY_BOC}\"}" \
        --abi "${CONFIGS_DIR}/SafeMultisigWallet.abi.json" \
        --sign "${KEYS_DIR}/msig.keys.json"; then
        echo "INFO: tonos-cli submitTransaction attempt #${i}... FAIL"
    else
        echo "INFO: tonos-cli submitTransaction attempt #${i}... PASS"
        break
    fi
    set +x
done

if [ "$i" = ${TONOS_CLI_SEND_ATTEMPTS} ]; then
    echo "ERROR: unable to send an elector request - ${TONOS_CLI_SEND_ATTEMPTS} attempts failed"
    exit 1
fi

date +"INFO: %F %T prepared for elections"
echo "${ACTIVE_ELECTION_ID}" >"${ELECTIONS_WORK_DIR}/active-election-id-submitted"

rm -rf "${TMP_DIR}"
echo "INFO: $(basename "$0") END $(date +%s) / $(date)"
