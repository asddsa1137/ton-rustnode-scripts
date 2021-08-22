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
PROXY0_ADDR_FILE="${KEYS_DIR}/proxy0.addr"
PROXY1_ADDR_FILE="${KEYS_DIR}/proxy1.addr"

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

if [ ! -f "${PROXY0_ADDR_FILE}" ]; then
    echo "ERROR: "${PROXY0_ADDR_FILE}" does not exist"
    exit 1
fi
PROXY0_ADDR=$(cat "${PROXY0_ADDR_FILE}")

if [ ! -f "${PROXY1_ADDR_FILE}" ]; then
    echo "ERROR: "${PROXY1_ADDR_FILE}" does not exist"
    exit 1
fi
PROXY1_ADDR=$(cat "${PROXY1_ADDR_FILE}")

if [ -f "${HELPER_ADDR_FILE}" ]; then
    HELPER_ADDR=$(cat "${HELPER_ADDR_FILE}")
fi

echo "INFO: MSIG_ADDR = ${MSIG_ADDR}"
echo "INFO: DEPOOL_ADDR = ${DEPOOL_ADDR}"

ELECTIONS_END_BEFORE=$(${SCRIPT_DIR}/check_node_sync_status.sh |grep elections_end_before |awk '{print $2}' |sed 's/,//g')
ELECTIONS_START_BEFORE=$(${SCRIPT_DIR}/check_node_sync_status.sh |grep elections_start_before |awk '{print $2}' |sed 's/,//g')
STAKE_HELD_FOR=$(${SCRIPT_DIR}/check_node_sync_status.sh |grep stake_held_for |awk '{print $2}' |sed 's/,//g')
VALIDATORS_ELECTED_FOR=$(${SCRIPT_DIR}/check_node_sync_status.sh |grep validators_elected_for |awk '{print $2}' |sed 's/,//g')

ACTIVE_ELECTION_ID_HEX=$(${UTILS_DIR}/tonos-cli run ${ELECTOR_ADDR} active_election_id {} --abi ${CONFIGS_DIR}/Elector.abi.json 2>&1 | grep "value0" | awk '{print $2}' | tr -d '"') || true
if [ -z "${ACTIVE_ELECTION_ID_HEX}" ]; then
    echo "WARN: tonos-cli is feeling bad. Taking election id from status"
    ACTIVE_ELECTION_ID_HEX=$(${SCRIPT_DIR}/check_node_sync_status.sh |grep utime_until |awk '{print $2}' |sed 's/,//g')
    if [ -z "${ACTIVE_ELECTION_ID_HEX}" ]; then
        echo "ERROR: failed to get active elections ID"
        exit 1
    fi
fi
ACTIVE_ELECTION_ID=$(printf "%d" "${ACTIVE_ELECTION_ID_HEX}")
echo "INFO: ACTIVE_ELECTION_ID = ${ACTIVE_ELECTION_ID}"

NOW=$(date +%s)
ELECTIONS_START=$(($ACTIVE_ELECTION_ID - $ELECTIONS_START_BEFORE))
ELECTIONS_END=$(($ACTIVE_ELECTION_ID - $ELECTIONS_END_BEFORE))
if [ "${ACTIVE_ELECTION_ID}" = "0" ] || [ $NOW -lt $ELECTIONS_START ] || [ $NOW -gt $ELECTIONS_END ]; then
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

"${UTILS_DIR}/tonos-cli" depool --addr "${DEPOOL_ADDR}" events >"${ELECTIONS_WORK_DIR}/events.txt" 2>&1 || true

set +eE
ACTIVE_ELECTION_ID_FROM_DEPOOL_EVENT=$(grep "^{" "${ELECTIONS_WORK_DIR}/events.txt" | grep electionId |
    jq ".electionId" | head -1 | tr -d '"')
if [ -z "${ACTIVE_ELECTION_ID_FROM_DEPOOL_EVENT}" ]; then
    echo "WARN: tonos-cli is feeling bad. Taking depool election id from ACTIVE_ELECTION_ID"
    ACTIVE_ELECTION_ID_FROM_DEPOOL_EVENT="${ACTIVE_ELECTION_ID}"
fi
echo "INFO: ACTIVE_ELECTION_ID_FROM_DEPOOL_EVENT = ${ACTIVE_ELECTION_ID_FROM_DEPOOL_EVENT}"

ACTIVE_ELECTION_ID_TIME_DIFF=$(($ACTIVE_ELECTION_ID - $ACTIVE_ELECTION_ID_FROM_DEPOOL_EVENT))
if [ -f "${ELECTIONS_WORK_DIR}/${ACTIVE_ELECTION_ID}-tick-body.boc" ]; then
    if [ $ACTIVE_ELECTION_ID_TIME_DIFF -gt 1000 ]; then
	    echo "WARN: We already sent ticktock but events shows an old electionId. DApp is out of sync! Take electionId from status."
            ACTIVE_ELECTION_ID_FROM_DEPOOL_EVENT="${ACTIVE_ELECTION_ID}"
    fi
    PROXY_ADDR_FROM_DEPOOL_EVENT=$(grep "^{" "${ELECTIONS_WORK_DIR}/events.txt" | grep electionId |
        jq ".proxy" | head -1 | tr -d '"')
    if [ -z "${PROXY_ADDR_FROM_DEPOOL_EVENT}" ]; then
	echo "WARN: tonos-cli is feeling bad. Try to figure out required proxy address based on previous elections."
	# Get proxy used in previous elections and take other one
	POSSIBLE_PROXY="$(cat ${KEYS_DIR}/elections/$((${ACTIVE_ELECTION_ID}-${VALIDATORS_ELECTED_FOR}))/proxy.addr)"
	if [ -z ${POSSIBLE_PROXY} ]; then
	    echo "FATAL: Proxy used in last elections in unknown. I'm powerless here without local run methods."
	    exit 1
	fi
	if [ "${PROXY0_ADDR}" = "${POSSIBLE_PROXY}" ]; then
	    PROXY_ADDR_FROM_DEPOOL_EVENT="${PROXY1_ADDR}"
	else
	    PROXY_ADDR_FROM_DEPOOL_EVENT="${PROXY0_ADDR}"
	fi
    fi
    echo "INFO: PROXY_ADDR_FROM_DEPOOL_EVENT = ${PROXY_ADDR_FROM_DEPOOL_EVENT}"
else
    echo "INFO: Ticktock required."
    if [ ! -z "${HELPER_ADDR}" ]; then
        # create contract bin key for tvm linker
        HELPER_ADDR=`cat "${HELPER_ADDR_FILE}" | cut -d ':' -f 2`
        HELPER_PUBLIC=`cat "${KEYS_DIR}/helper.json" | jq -r ".public"`
        HELPER_SECRET=`cat "${KEYS_DIR}/helper.json" | jq -r ".secret"`
        if [[ -z $HELPER_PUBLIC ]] || [[ -z $HELPER_SECRET ]]; then
            echo "FATAL: helper keys are empty"
            exit 1
        fi
        echo "${HELPER_SECRET}${HELPER_PUBLIC}" > "${KEYS_DIR}/helper.txt"
        rm -f "${KEYS_DIR}/helper.bin"
        xxd -r -p "${KEYS_DIR}/helper.txt" "${KEYS_DIR}/helper.bin"

        #generate boc
        TVM_OUTPUT=$("${UTILS_DIR}/tvm_linker" message "${HELPER_ADDR}" -a "${CONTRACTS_DIR}/depool/DePoolHelper.abi.json" -m sendTicktock -p "{}" -w 0 --setkey "${KEYS_DIR}/helper.bin")
        if [[ -z $(echo $TVM_OUTPUT | grep "boc file created") ]]; then
            echo "FATAL: tvm_linker unable to create boc"
            exit 1
        fi
        mv -f "$(echo "${HELPER_ADDR}"| cut -c 1-8)-msg-body.boc" "${ELECTIONS_WORK_DIR}/${ACTIVE_ELECTION_ID}-tick-body.boc"

        echo "INFO: try to ticktock"
        set -x
        if ! [[ -n $("${UTILS_DIR}/console" -C "${TON_WORK_DIR}/configs/console.json" --cmd "sendmessage ${ELECTIONS_WORK_DIR}/${ACTIVE_ELECTION_ID}-tick-body.boc" | grep -i 'success') ]]; then
            echo "FATAL: rconsole sendmessage Ticktock attempt FAIL"
	    rm -f "${ELECTIONS_WORK_DIR}/${ACTIVE_ELECTION_ID}-tick-body.boc"
	    exit 1
        else
            echo "INFO: rconsole sendmessage Ticktock attempt PASS"
        fi
        set +x
    fi
    exit 0
fi
set -eE

ELECTIONS_ARTEFACTS_CREATED="0"
if [ -f "${ELECTIONS_WORK_DIR}/election-artefacts-created" ] &&
    [ "${ACTIVE_ELECTION_ID_FROM_DEPOOL_EVENT}" = "$(cat "${ELECTIONS_WORK_DIR}/election-artefacts-created")" ]; then
    ELECTIONS_ARTEFACTS_CREATED="1"
fi

if [ "${ELECTIONS_ARTEFACTS_CREATED}" = "0" ]; then
   echo "INFO: ELECTIONS_START_BEFORE = ${ELECTIONS_START_BEFORE}"
   echo "INFO: ELECTIONS_END_BEFORE = ${ELECTIONS_END_BEFORE}"
   echo "INFO: STAKE_HELD_FOR = ${STAKE_HELD_FOR}"
   echo "INFO: VALIDATORS_ELECTED_FOR = ${VALIDATORS_ELECTED_FOR}"

   ELECTION_START="${ACTIVE_ELECTION_ID_FROM_DEPOOL_EVENT}"
   # TODO: duration may be reduced - to be checked
   ELECTION_STOP=$((ACTIVE_ELECTION_ID_FROM_DEPOOL_EVENT + 1000 + ELECTIONS_START_BEFORE + ELECTIONS_END_BEFORE + STAKE_HELD_FOR + VALIDATORS_ELECTED_FOR))

   echo "${PROXY_ADDR_FROM_DEPOOL_EVENT}" > "${ELECTIONS_WORK_DIR}/proxy.addr"
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

# create contract bin key for tvm linker
MSIG_ADDR=`cat "${MSIG_ADDR_FILE}" | cut -d ':' -f 2`
MSIG_PUBLIC=`cat "${KEYS_DIR}/msig.keys.json" | jq -r ".public"`
MSIG_SECRET=`cat "${KEYS_DIR}/msig.keys.json" | jq -r ".secret"`
if [[ -z $MSIG_PUBLIC ]] || [[ -z $MSIG_SECRET ]]; then
    echo "FATAL: msig keys are empty"
    exit 1
fi
echo "${MSIG_SECRET}${MSIG_PUBLIC}" > "${KEYS_DIR}/msig.keys.txt"
rm -f "${KEYS_DIR}/msig.keys.bin"
xxd -r -p "${KEYS_DIR}/msig.keys.txt" "${KEYS_DIR}/msig.keys.bin"

#generate boc
TVM_OUTPUT=$("${UTILS_DIR}/tvm_linker" message "${MSIG_ADDR}" -a "${CONFIGS_DIR}/SafeMultisigWallet.abi.json" -m submitTransaction -p "{\"dest\":\"${DEPOOL_ADDR}\",\"value\":\"1000000000\",\"bounce\":true,\"allBalance\":false,\"payload\":\"${VALIDATOR_QUERY_BOC}\"}" -w 0 --setkey "${KEYS_DIR}/msig.keys.bin")
if [[ -z $(echo $TVM_OUTPUT | grep "boc file created") ]]; then
    echo "FATAL: tvm_linker unable to create boc"
    exit 1
fi
mv -f "$(echo "${MSIG_ADDR}"| cut -c 1-8)-msg-body.boc" "${ELECTIONS_WORK_DIR}/${ACTIVE_ELECTION_ID}-msg-body.boc"

echo "INFO: rconsole submitTransaction attempt #${i}..."
set -x
if ! [[ -n $("${UTILS_DIR}/console" -C "${TON_WORK_DIR}/configs/console.json" --cmd "sendmessage ${ELECTIONS_WORK_DIR}/${ACTIVE_ELECTION_ID}-msg-body.boc" | grep -i 'success') ]]; then
    echo "INFO: rconsole submitTransaction attempt FAIL"
    exit 1
else
    echo "INFO: rconsole submitTransaction attempt PASS"
fi
set +x

date +"INFO: %F %T prepared for elections"
echo "${ACTIVE_ELECTION_ID}" >"${ELECTIONS_WORK_DIR}/active-election-id-submitted"

rm -rf "${TMP_DIR}"
echo "INFO: $(basename "$0") END $(date +%s) / $(date)"
