#!/bin/bash

set -eux
cd "$(dirname "$0")"

OPEN_URL=false

# we will re-run the btcpayserver provisioning scripts if directed to do so.
# if an update does occur, we grab another backup.
if [ "$UPDATE_BTCPAY" = true ]; then
    # run the update.
    ssh "$FQDN" "bash -c $BTCPAY_SERVER_APPPATH/btcpay-down.sh"

    # btcpay-update.sh brings services back up, but does not take them down.
    ssh "$FQDN" "sudo bash -c $BTCPAY_SERVER_APPPATH/btcpay-update.sh"

elif [ "$RESTORE_BTCPAY" = true ]; then
    # run the update.
    ssh "$FQDN" "bash -c $BTCPAY_SERVER_APPPATH/btcpay-down.sh"

    ./restore.sh

    RUN_BACKUP=false
    RUN_SERVICES=true
    OPEN_URL=true

elif [ "$RECONFIGURE_BTCPAY_SERVER" == true ]; then
    # the administrator may have indicated a reconfig;
    # if so, we re-run setup script.
    ./run_setup.sh
    exit
fi

# if the script gets this far, then we grab a regular backup.
if [ "$RUN_BACKUP"  = true ]; then
    # we just grab a regular backup
    ./backup.sh "$UNIX_BACKUP_TIMESTAMP"
fi


if [ "$RUN_SERVICES" = true ]; then
    # The default is to resume services, though admin may want to keep services off (eg., for a migration)
    # we bring the services back up by default.
    ssh "$FQDN" "bash -c $BTCPAY_SERVER_APPPATH/btcpay-up.sh"
    OPEN_URL=true

fi

if [ "$OPEN_URL" = true ]; then
    if wait-for-it -t 5 "$FQDN:443"; then
        xdg-open "https://$FQDN"
    fi
fi