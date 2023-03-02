#!/bin/bash

set -ex
cd "$(dirname "$0")"

# take the services down, create a backup archive, then pull it down.
# the script executed here from the BTCPAY repo will automatically take services down
# and bring them back up.

echo "INFO: Starting BTCPAY Backup script for host '$BTCPAY_FQDN'."

sleep 5

ssh "$BTCPAY_FQDN" "mkdir -p $REMOTE_HOME/backups; cd $REMOTE_HOME/; sudo BTCPAY_BASE_DIRECTORY=$REMOTE_HOME bash -c $BTCPAY_SERVER_APPPATH/btcpay-down.sh"

# TODO; not sure if this is necessary, but we want to give the VM additional time to take down all services
# that way processes can run shutdown procedures and leave files in the correct state.
sleep 10

# TODO enable encrypted archives
# TODO switch to btcpay-backup.sh when on LXD fully.
scp ./remote_scripts/btcpay-backup.sh "$BTCPAY_FQDN:$REMOTE_HOME/btcpay-backup.sh"
ssh "$BTCPAY_FQDN" "sudo cp $REMOTE_HOME/btcpay-backup.sh $BTCPAY_SERVER_APPPATH/btcpay-backup.sh && sudo chmod 0755 $BTCPAY_SERVER_APPPATH/btcpay-backup.sh"
ssh "$BTCPAY_FQDN" "cd $REMOTE_HOME/; sudo BTCPAY_BASE_DIRECTORY=$REMOTE_HOME BTCPAY_DOCKER_COMPOSE=$REMOTE_HOME/btcpayserver-docker/Generated/docker-compose.generated.yml bash -c $BTCPAY_SERVER_APPPATH/btcpay-backup.sh"

# next we pull the resulting backup archive down to our management machine.
ssh "$BTCPAY_FQDN" "sudo cp /var/lib/docker/volumes/backup_datadir/_data/backup.tar.gz $REMOTE_HOME/backups/btcpay.tar.gz"
ssh "$BTCPAY_FQDN" "sudo chown ubuntu:ubuntu $REMOTE_HOME/backups/btcpay.tar.gz"

# if the backup archive path is not set, then we set it. It is usually set only when we are running a migration script.
BTCPAY_LOCAL_BACKUP_PATH="$SITES_PATH/$PRIMARY_DOMAIN/backups/btcpayserver"
if [ -z "$BACKUP_BTCPAY_ARCHIVE_PATH" ]; then
    BACKUP_BTCPAY_ARCHIVE_PATH="$BTCPAY_LOCAL_BACKUP_PATH/$(date +%s).tar.gz"
fi

mkdir -p "$BTCPAY_LOCAL_BACKUP_PATH"
scp "$BTCPAY_FQDN:$REMOTE_HOME/backups/btcpay.tar.gz" "$BACKUP_BTCPAY_ARCHIVE_PATH"

echo "INFO: Created backup archive '$BACKUP_BTCPAY_ARCHIVE_PATH' for host '$BTCPAY_FQDN'."
