
#!/bin/bash -eE

TON_WORK_DIR="/var/ton-node"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=env.sh
. "${SCRIPT_DIR}/env.sh"

TOOLS_DIR="${SRC_TOP_DIR}/tools"

"${TOOLS_DIR}/console" -C "${TON_WORK_DIR}/configs/console.json" --cmd getstats
