#!/bin/bash

set -e
cd "$(dirname "$0")"

if [ -f "$BACKUP_BTCPAY_ARCHIVE_PATH" ]; then
    # push the restoration archive to the remote server
    echo "INFO: Restoring BTCPAY Server: $BACKUP_BTCPAY_ARCHIVE_PATH"

    BTCPAY_REMOTE_BACKUP_PATH="$REMOTE_BACKUP_PATH/btcpayserver"
    ssh "$FQDN" mkdir -p "$BTCPAY_REMOTE_BACKUP_PATH"
    REMOTE_BTCPAY_ARCHIVE_PATH="$BTCPAY_REMOTE_BACKUP_PATH/btcpay.tar.gz"
    scp "$BACKUP_BTCPAY_ARCHIVE_PATH" "$FQDN:$REMOTE_BTCPAY_ARCHIVE_PATH"

    # push the modified restore script to the remote directory, set permissions, and execute.
    scp ./remote_scripts/btcpay-restore.sh "$FQDN:$REMOTE_DATA_PATH/btcpay-restore.sh"
    ssh "$FQDN" "sudo mv $REMOTE_DATA_PATH/btcpay-restore.sh $BTCPAY_SERVER_APPPATH/btcpay-restore.sh && sudo chmod 0755 $BTCPAY_SERVER_APPPATH/btcpay-restore.sh"
    ssh "$FQDN" "cd $REMOTE_DATA_PATH/; sudo BTCPAY_BASE_DIRECTORY=$REMOTE_DATA_PATH BTCPAY_DOCKER_COMPOSE=$REMOTE_DATA_PATH/btcpayserver-docker/Generated/docker-compose.generated.yml bash -c '$BTCPAY_SERVER_APPPATH/btcpay-restore.sh $REMOTE_BTCPAY_ARCHIVE_PATH'"
fi
