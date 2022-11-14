#!/bin/bash

set -eu
cd "$(dirname "$0")"

export DOCKER_HOST="ssh://ubuntu@$BTCPAY_FQDN"

OPEN_URL=true
RUN_SERVICES=true

# we will re-run the btcpayserver provisioning scripts if directed to do so.
# if an update does occur, we grab another backup.
if [ "$UPDATE_BTCPAY" = true ]; then
    # run the update.
    ssh "$FQDN" "bash -c $BTCPAY_SERVER_APPPATH/btcpay-down.sh"

    # btcpay-update.sh brings services back up, but does not take them down.
    ssh "$FQDN" "sudo bash -c $BTCPAY_SERVER_APPPATH/btcpay-update.sh"

    sleep 20

elif [ "$RESTORE_BTCPAY" = true ]; then
    # run the update.
    ssh "$FQDN" "bash -c $BTCPAY_SERVER_APPPATH/btcpay-down.sh"
    sleep 15
    
    ./restore.sh

    RUN_SERVICES=true
    OPEN_URL=true

elif [ "$RECONFIGURE_BTCPAY_SERVER" == true ]; then
    # the administrator may have indicated a reconfig;
    # if so, we re-run setup script.
    ./stub_btcpay_setup.sh

    RUN_SERVICES=true
    OPEN_URL=true
fi

# if the script gets this far, then we grab a regular backup.
if [ "$BACKUP_BTCPAY"  = true ]; then
    # we just grab a regular backup
    ./backup_btcpay.sh
fi

if [ "$RUN_SERVICES" = true ]; then
    # The default is to resume services, though admin may want to keep services off (eg., for a migration)
    # we bring the services back up by default.
    ssh "$FQDN" "bash -c $BTCPAY_SERVER_APPPATH/btcpay-up.sh"

    OPEN_URL=true

fi

if [ "$OPEN_URL" = true ]; then
    if wait-for-it -t 5 "$PRIMARY_WWW_FQDN:80"; then
        xdg-open "http://$PRIMARY_WWW_FQDN" > /dev/null 2>&1
    fi
fi
