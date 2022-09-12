#!/bin/bash

###################################################
# und Quick Upgrade script                        #
#                                                 #
# Requires jq & curl. Install using, for example: #
#   sudo yum install jq curl -y                   #
###################################################

##########
# CONFIG #
##########

# path to .und_mainchain
UND_HOME="${HOME}/.und_mainchain"

# path to download und 1.5.1 and unpack
UPGRADE_TMP="/tmp/und_upgrade"

# path to save old und binaries & .und_mainchain/config directory
BACKUP_DIR="${HOME}/und_backup"

# install path for und and undcli
# undcli is no longer used and will be removed during upgrade
# all previous undcli commands are now handled by the und binary
UND_PATH="/usr/local/bin/und"
UNDCLI_PATH="/usr/local/bin/undcli"

# name of /etc/systemd/system/und.service used to start/stop via systemctl command
SYSTEMD_SERVICE="und"

##########
# SCRIPT #
##########

if ! command -v jq &> /dev/null
then
  echo "jq could not be found. Install and run the script again, for example:"
  echo "  sudo yum install jq -y"
  exit 1
fi

if ! command -v curl &> /dev/null
then
  echo "curl could not be found. Install and run the script again, for example:"
  echo "  sudo yum install curl -y"
  exit 1
fi

echo "create dirs"
mkdir -p "${UPGRADE_TMP}"
mkdir -p "${BACKUP_DIR}"

echo "stop ${SYSTEMD_SERVICE}"
sudo systemctl stop ${SYSTEMD_SERVICE}

echo "backup .und_mainchain/config"
cd "${UND_HOME}"/config || exit
tar -cpzf "${BACKUP_DIR}"/und_mainchain_1.4.8.config.backup.tar.gz *

echo "backup binaries & remove undcli"
cp "${UND_PATH}" "${BACKUP_DIR}"/und_1.4.8
cp "${UNDCLI_PATH}" "${BACKUP_DIR}"/undcli_1.4.8
sudo rm "${UNDCLI_PATH}"

cd "${UPGRADE_TMP}" || exit

echo "download und v1.5.1"
curl -L https://github.com/unification-com/mainchain/releases/download/1.5.1/und_v1.5.1_linux_x86_64.tar.gz -o und_v1.5.1_linux_x86_64.tar.gz
tar -zxvf und_v1.5.1_linux_x86_64.tar.gz
sudo mv und "${UND_PATH}"

echo "update config.toml"
sed -i -e 's/log_level = "\(.*\)"/log_level = "info"/gi' "${UND_HOME}/config/config.toml"

echo "unsafe-reset-all"
"${UND_PATH}" unsafe-reset-all --home="${UND_HOME}"

echo "download genesis.json & app.toml"
curl https://raw.githubusercontent.com/unification-com/mainnet/master/latest/genesis.json > "${UND_HOME}"/config/genesis.json
curl https://raw.githubusercontent.com/unification-com/mainnet/master/latest/042_app.toml > "${UND_HOME}"/config/app.toml

echo "update app.toml"
sed -i -e 's/snapshot-interval = 0/snapshot-interval = 500/gi' "${UND_HOME}/config/app.toml"
sed -i -e 's/snapshot-keep-recent = 2/snapshot-keep-recent = 4/gi' "${UND_HOME}/config/app.toml"

echo "get snapshot info & write to config.toml"

BLOCK_JSON=$(curl -s https://rest.unification.io/blocks/latest)
TRUST_HEIGHT=$(echo "${BLOCK_JSON}" | jq --raw-output '.block.header.height')
TRUST_HASH=$(echo "${BLOCK_JSON}" | jq --raw-output '.block_id.hash')

cat >> "${UND_HOME}/config/config.toml" <<EOF

#######################################################
###         State Sync Configuration Options        ###
#######################################################
[statesync]
# State sync rapidly bootstraps a new node by discovering, fetching, and restoring a state machine
# snapshot from peers instead of fetching and replaying historical blocks. Requires some peers in
# the network to take and serve state machine snapshots. State sync is not attempted if the node
# has any local state (LastBlockHeight > 0). The node will have a truncated block history,
# starting from the height of the snapshot.
enable = true

# RPC servers (comma-separated) for light client verification of the synced state machine and
# retrieval of state data for node bootstrapping. Also needs a trusted height and corresponding
# header hash obtained from a trusted source, and a period during which validators can be trusted.
#
# For Cosmos SDK-based chains, trust_period should usually be about 2/3 of the unbonding time (~2
# weeks) during which they can be financially punished (slashed) for misbehavior.
rpc_servers = "sync1.unification.io:26657,sync2.unification.io:26657"
trust_height = $TRUST_HEIGHT
trust_hash = "$TRUST_HASH"
trust_period = "168h0m0s"

# Time to spend discovering snapshots before initiating a restore.
discovery_time = "15s"

# Temporary directory for state sync snapshot chunks, defaults to the OS tempdir (typically /tmp).
# Will create a new, randomly named directory within, and remove it when done.
temp_dir = ""

EOF

echo "start node"

sudo systemctl start "${SYSTEMD_SERVICE}"

echo "Upgrade complete."
echo "to check status, run:"
echo ""
echo "  sudo journalctl -u ${SYSTEMD_SERVICE} -f"
echo ""
echo "Once fully synced, and if required, unjail your node:"
echo ""
echo "und tx slashing unjail --gas auto --gas-adjustment 1.5 --gas-prices 25.0nund --chain-id FUND-MainNet-2 --node https://rpc1.unification.io:443 --from MY_STAKING_ACCOUNT"
echo ""
