#!/bin/bash

set -eu
cd "$(dirname "$0")"

if [ "$VIRTUAL_MACHINE" = btcpayserver ]; then
    # send an updated ~/.bashrc so we have quicker access to cli tools
    scp ./bashrc.txt "ubuntu@$BTCPAY_SERVER_FQDN:$REMOTE_HOME/.bashrc"
    ssh "$BTCPAY_SERVER_FQDN" "chown ubuntu:ubuntu $REMOTE_HOME/.bashrc"
    ssh "$BTCPAY_SERVER_FQDN" "chmod 0664 $REMOTE_HOME/.bashrc"
fi

./stub_btcpay_setup.sh

# we will re-run the btcpayserver provisioning scripts if directed to do so.
# if an update does occur, we grab another backup.
if [ "$UPDATE_BTCPAY" = true ]; then
    # run the update.
    ssh "$BTCPAY_SERVER_FQDN" "bash -c $BTCPAY_SERVER_APPPATH/btcpay-down.sh"

    # btcpay-update.sh brings services back up, but does not take them down.
    ssh "$BTCPAY_SERVER_FQDN" "sudo bash -c $BTCPAY_SERVER_APPPATH/btcpay-update.sh"

    sleep 30

elif [ "$RESTORE_BTCPAY" = true ]; then
    # run the update.
    ssh "$BTCPAY_SERVER_FQDN" "bash -c $BTCPAY_SERVER_APPPATH/btcpay-down.sh"
    sleep 15
    
    ./restore.sh

    BACKUP_BTCPAY=false
fi

# The default is to resume services, though admin may want to keep services off (eg., for a migration)
# we bring the services back up by default.
ssh "$BTCPAY_SERVER_FQDN" "bash -c $BTCPAY_SERVER_APPPATH/btcpay-up.sh"

