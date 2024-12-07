#!/bin/bash

set -e
cd "$(dirname "$0")"



# default is for regtest
CLIGHTNING_WEBSOCKET_PORT=9736
if [ "$BITCOIN_CHAIN" = testnet ]; then
    CLIGHTNING_WEBSOCKET_PORT=9737
elif [ "$BITCOIN_CHAIN" = mainnet ]; then
    CLIGHTNING_WEBSOCKET_PORT=9738
fi

export CLIGHTNING_WEBSOCKET_PORT="$CLIGHTNING_WEBSOCKET_PORT"


# export BTCPAY_FASTSYNC_ARCHIVE_FILENAME="utxo-snapshot-bitcoin-testnet-1445586.tar"
# BTCPAY_REMOTE_RESTORE_PATH="/var/lib/docker/volumes/generated_bitcoin_datadir/_data"

# This is the config for a basic proxy to the listening port 127.0.0.1:2368
# It also supports modern TLS, so SSL certs must be available.
#opt-add-nostr-relay;

export BTCPAYSERVER_GITREPO="https://github.com/btcpayserver/btcpayserver-docker"

cat > "$SITE_PATH/btcpay.sh" <<EOL
#!/bin/bash

set -e
cd "\$(dirname "\$0")"

# wait for cloud-init to complete yo
while [ ! -f /var/lib/cloud/instance/boot-finished ]; do
    sleep 1
done

if [ ! -d "btcpayserver-docker" ]; then 
    echo "cloning btcpayserver-docker"; 
    git clone -b master ${BTCPAYSERVER_GITREPO} btcpayserver-docker;
    git config --global --add safe.directory /home/ubuntu/ss-data/btcpayserver-docker
else
    cd ./btcpayserver-docker
    git pull
    git pull --all --tags
    cd -
fi

cd btcpayserver-docker

export BTCPAY_HOST="${BTCPAY_USER_FQDN}"
export BTCPAY_ANNOUNCEABLE_HOST="${BTCPAY_USER_FQDN}"
export NBITCOIN_NETWORK="${BITCOIN_CHAIN}"
export LIGHTNING_ALIAS="${PRIMARY_DOMAIN}"
export BTCPAYGEN_LIGHTNING="clightning"
export BTCPAYGEN_CRYPTO1="btc"
export BTCPAYGEN_ADDITIONAL_FRAGMENTS="opt-save-storage-s;bitcoin-clightning.custom;"
export BTCPAYGEN_REVERSEPROXY="nginx"
export BTCPAY_ENABLE_SSH=false
export BTCPAY_BASE_DIRECTORY=${REMOTE_DATA_PATH}
export BTCPAYGEN_EXCLUDE_FRAGMENTS="nginx-https;"
export REVERSEPROXY_DEFAULT_HOST="$BTCPAY_USER_FQDN"

# next we create fragments to customize various aspects of the system
# this block customizes clightning to ensure the correct endpoints are being advertised
# We want to advertise the correct ipv4 endpoint for remote hosts to get in touch.
cat > ${REMOTE_DATA_PATH}/btcpayserver-docker/docker-compose-generator/docker-fragments/bitcoin-clightning.custom.yml <<EOF

services:
  clightning_bitcoin:
    environment:
      LIGHTNINGD_OPT: |
        announce-addr-dns=true
        bind-addr=ws::9736
        experimental-peer-storage
        experimental-offers
EOL

# if [ "$DEPLOY_CLBOSS_PLUGIN" = true ]; then
#     cat >> "$SITE_PATH/btcpay.sh" <<EOL
#         plugin=/root/.lightning/plugins/clboss
# EOL
# fi

cat >> "$SITE_PATH/btcpay.sh" <<EOL
    ports:
      - "${CLIGHTNING_WEBSOCKET_PORT}:9736"
    expose:
      - "9736"

EOF

# run the setup script.
. ./btcpay-setup.sh -i

touch ${REMOTE_DATA_PATH}/btcpay.complete
chown ubuntu:ubuntu ${REMOTE_DATA_PATH}/btcpay.complete
EOL


# send the setup script to the remote machine.
scp "$SITE_PATH/btcpay.sh" "ubuntu@$BTCPAY_SERVER_FQDN:$REMOTE_DATA_PATH/btcpay_setup.sh"
ssh "$BTCPAY_SERVER_FQDN" "chmod 0744 $REMOTE_DATA_PATH/btcpay_setup.sh"

# script is executed under sudo
ssh "$BTCPAY_SERVER_FQDN" "sudo bash -c $REMOTE_DATA_PATH/btcpay_setup.sh"

# lets give time for the containers to spin up
sleep 10