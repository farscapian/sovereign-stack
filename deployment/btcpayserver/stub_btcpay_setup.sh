#!/bin/bash

set -ex
cd "$(dirname "$0")"

# export BTCPAY_FASTSYNC_ARCHIVE_FILENAME="utxo-snapshot-bitcoin-testnet-1445586.tar"
# BTCPAY_REMOTE_RESTORE_PATH="/var/lib/docker/volumes/generated_bitcoin_datadir/_data"

# This is the config for a basic proxy to the listening port 127.0.0.1:2368
# It also supports modern TLS, so SSL certs must be available.
cat > "$SITE_PATH/btcpay.sh" <<EOL
#!/bin/bash

set -ex
cd "\$(dirname "\$0")"

# wait for cloud-init to complete yo
while [ ! -f /var/lib/cloud/instance/boot-finished ]; do
    sleep 1
done

if [ ! -d "btcpayserver-docker" ]; then 
    echo "cloning btcpayserver-docker"; 
    git clone -b master https://github.com/btcpayserver/btcpayserver-docker btcpayserver-docker;
    git config --global --add safe.directory /home/ubuntu/btcpayserver-docker
else
    cd ./btcpayserver-docker
    git pull
    git pull --all --tags
    cd -
fi

cd btcpayserver-docker

export BTCPAY_HOST="${BTCPAY_USER_FQDN}"
export NBITCOIN_NETWORK="${BTC_CHAIN}"
export LIGHTNING_ALIAS="${DOMAIN_NAME}"
export BTCPAYGEN_LIGHTNING="clightning"
export BTCPAYGEN_CRYPTO1="btc"
export BTCPAYGEN_ADDITIONAL_FRAGMENTS="opt-save-storage-s;opt-add-btctransmuter;opt-add-nostr-relay;"
export BTCPAYGEN_REVERSEPROXY="nginx"
export BTCPAY_ENABLE_SSH=false
export BTCPAY_BASE_DIRECTORY=${REMOTE_HOME}
export BTCPAYGEN_EXCLUDE_FRAGMENTS="nginx-https"
export REVERSEPROXY_DEFAULT_HOST="$BTCPAY_USER_FQDN"

if [ "\$NBITCOIN_NETWORK" != regtest ]; then
    # run fast_sync if it's not been done before.
    if [ ! -f /home/ubuntu/fast_sync_completed ]; then
        cd ./contrib/FastSync
        ./load-utxo-set.sh
        touch /home/ubuntu/fast_sync_completed
        cd -
    fi
fi

# run the setup script.
. ./btcpay-setup.sh -i

EOL

# send an updated ~/.bashrc so we have quicker access to cli tools
scp ./bashrc.txt "ubuntu@$FQDN:$REMOTE_HOME/.bashrc"
ssh "$BTCPAY_FQDN" "chown ubuntu:ubuntu $REMOTE_HOME/.bashrc"
ssh "$BTCPAY_FQDN" "chmod 0664 $REMOTE_HOME/.bashrc"

# send the setup script to the remote machine.
scp "$SITE_PATH/btcpay.sh" "ubuntu@$FQDN:$REMOTE_HOME/btcpay_setup.sh"
ssh "$BTCPAY_FQDN" "chmod 0744 $REMOTE_HOME/btcpay_setup.sh"
ssh "$BTCPAY_FQDN" "sudo bash -c ./btcpay_setup.sh"
ssh "$BTCPAY_FQDN" "touch $REMOTE_HOME/btcpay.complete"
