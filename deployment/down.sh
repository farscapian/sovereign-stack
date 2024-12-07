#!/bin/bash

# https://www.sovereign-stack.org/ss-down/

set -exu
cd "$(dirname "$0")"

if incus remote get-default -q | grep -q "local"; then
    echo "ERROR: you are on the local incus remote. Nothing to take down"
    exit 1
fi

KEEP_ZFS_STORAGE_VOLUMES=true
OTHER_SITES_LIST=
SKIP_BTCPAY_SERVER=false
SKIP_WWW_SERVER=false
SKIP_LNPLAY_SERVER=false
BACKUP_WWW_APPS=true

WWW_SERVER_MAC_ADDRESS=
BTCPAY_SERVER_MAC_ADDRESS=
LNPLAY_SERVER_MAC_ADDRESS=

# grab any modifications from the command line.
for i in "$@"; do
    case $i in
        --purge)
            KEEP_ZFS_STORAGE_VOLUMES=false
            shift
        ;;
        --skip-btcpayserver)
            SKIP_BTCPAY_SERVER=true
            shift
        ;;
        --skip-wwwserver)
            SKIP_WWW_SERVER=true
            shift
        ;;
        --skip-lnplayserver)
            SKIP_LNPLAY_SERVER=true
            shift
        ;;
        --skip-wwwbackup)
            BACKUP_WWW_APPS=false
            shift
        ;;
        *)
        echo "Unexpected option: $1"
        exit 1
        ;;
    esac
done

. ./deployment_defaults.sh

. ./remote_env.sh

. ./project_env.sh

# let's bring down services on the remote deployment if necessary.
export DOMAIN_NAME="$PRIMARY_DOMAIN"
export SITE_PATH="$SITES_PATH/$PRIMARY_DOMAIN"

source "$SITE_PATH/site.conf"
source ./project/domain_env.sh

source ./domain_list.sh


SERVERS=
if [ "$SKIP_WWW_SERVER" = false ] && [ -n "$WWW_SERVER_MAC_ADDRESS" ]; then
    SERVERS="www $SERVERS"
fi

if [ "$SKIP_BTCPAY_SERVER" = false ] && [ -n "$BTCPAY_SERVER_MAC_ADDRESS" ]; then
    SERVERS="$SERVERS btcpayserver"
fi

if [ "$SKIP_LNPLAY_SERVER" = false ] && [ -n "$LNPLAY_SERVER_MAC_ADDRESS" ]; then
    SERVERS="$SERVERS lnplayserver"
fi

for VIRTUAL_MACHINE in $SERVERS; do

    INCUS_VM_NAME="$VIRTUAL_MACHINE-${PRIMARY_DOMAIN//./-}"

    if incus list | grep -q "$INCUS_VM_NAME"; then
        bash -c "./stop.sh --server=$VIRTUAL_MACHINE"

        incus stop "$INCUS_VM_NAME"

        incus delete "$INCUS_VM_NAME"
    fi

    # remove the ssh known endpoint else we get warnings.
    ssh-keygen -f "$SSH_HOME/known_hosts" -R "$VIRTUAL_MACHINE.$PRIMARY_DOMAIN" | exit

    if incus profile list | grep -q "$INCUS_VM_NAME"; then
        incus profile delete "$INCUS_VM_NAME"
    fi

    if [ "$KEEP_ZFS_STORAGE_VOLUMES" = false ]; then
        # d for docker; b for backup; s for ss-data
        for DATA in docker backup ss-data; do
            VOLUME_NAME="$VIRTUAL_MACHINE-$DATA"
            if incus storage volume list ss-base -q | grep -q "$VOLUME_NAME"; then
                RESPONSE=
                read -r -p "Are you sure you want to delete the '$VOLUME_NAME' volume intended for '$INCUS_VM_NAME'?": RESPONSE
            
                if [ "$RESPONSE" = "y" ]; then
                    incus storage volume delete ss-base "$VOLUME_NAME"
                fi
            fi
        done
    fi
done

# let's grab a backup of the www
if [ "$BACKUP_WWW_APPS" = true ]; then
    SNAPSHOT_ID=$(cat /dev/urandom | tr -dc 'a-aA-Z' | fold -w 6 | head -n 1)
    incus storage volume snapshot create ss-base www-ss-data "$SNAPSHOT_ID"
    BACKUP_LOCATION="$HOME/ss/backups"
    mkdir -p "$BACKUP_LOCATION"
    incus storage volume export ss-base "www-ss-data" "$BACKUP_LOCATION/project-$(incus project list --format csv | grep "(current)" | awk '{print $1}')_www-ss-data_""$(date +%s)"".tar.gz"
    incus storage volume snapshot delete ss-base "www-ss-data" "$SNAPSHOT_ID"
fi

if [[ "$SERVERS" == *"www"* && "$SERVERS" == *"btcpay"* ]]; then
    if incus network list -q | grep -q ss-ovn; then
        incus network delete ss-ovn
    fi
fi