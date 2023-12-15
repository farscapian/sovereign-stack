#!/bin/bash

# https://www.sovereign-stack.org/ss-down/

set -exu
cd "$(dirname "$0")"

if incus remote get-default -q | grep -q "local"; then
    echo "ERROR: you are on the local incus remote. Nothing to take down"
    exit 1
fi

KEEP_DOCKER_VOLUME=true
OTHER_SITES_LIST=
SKIP_BTCPAY_SERVER=false
SKIP_WWW_SERVER=false
SKIP_LNPLAY_SERVER=false
BACKUP_WWW_APPS=true

# grab any modifications from the command line.
for i in "$@"; do
    case $i in
        --purge)
            KEEP_DOCKER_VOLUME=false
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
        *)
        echo "Unexpected option: $1"
        exit 1
        ;;
    esac
done

SERVERS=
if [ "$SKIP_BTCPAY_SERVER" = false ]; then
    SERVERS="btcpayserver"
fi

if [ "$SKIP_WWW_SERVER" = false ]; then
    SERVERS="www $SERVERS"
fi

if [ "$SKIP_LNPLAY_SERVER" = false ]; then
    SERVERS="lnplayserver $SERVERS"
fi

. ./deployment_defaults.sh

. ./remote_env.sh

. ./project_env.sh

# let's bring down services on the remote deployment if necessary.
export DOMAIN_NAME="$PRIMARY_DOMAIN"
export SITE_PATH="$SITES_PATH/$PRIMARY_DOMAIN"

source "$SITE_PATH/site.conf"
source ./project/domain_env.sh

source ./domain_list.sh

for VIRTUAL_MACHINE in $SERVERS; do

    INCUS_VM_NAME="$VIRTUAL_MACHINE-${PRIMARY_DOMAIN//./-}"

    if incus list | grep -q "$INCUS_VM_NAME"; then
        bash -c "./stop.sh --server=$VIRTUAL_MACHINE"

        # if [ "$VIRTUAL_MACHINE" = www ] && [ "$BACKUP_WWW_APPS" = true ]; then
        #     APP_LIST="letsencrypt ghost nextcloud gitea nostr"
        #     echo "INFO: Backing up WWW apps."
        #     for APP in $APP_LIST; do
        #         bash -c "$(pwd)/project/www/backup_www.sh --app=$APP"
        #     done
        # fi

        incus stop "$INCUS_VM_NAME"

        incus delete "$INCUS_VM_NAME"
    fi

    # remove the ssh known endpoint else we get warnings.
    ssh-keygen -f "$SSH_HOME/known_hosts" -R "$VIRTUAL_MACHINE.$PRIMARY_DOMAIN" | exit

    if incus profile list | grep -q "$INCUS_VM_NAME"; then
        incus profile delete "$INCUS_VM_NAME"
    fi

    if [ "$KEEP_DOCKER_VOLUME" = false ]; then

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
    else
        # we maintain the volumes
        # TODO make a snapshot on all the zfs storage volumes.
        echo "TODO: create snapshot of ZFS volumes and pull them to mgmt machine."
    fi
done

if incus network list -q | grep -q ss-ovn; then
    incus network delete ss-ovn
fi
