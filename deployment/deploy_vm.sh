#!/bin/bash

set -exu
cd "$(dirname "$0")"

. ./base.sh

## This is a weird if clause since we need to LEFT-ALIGN the statement below.
SSH_STRING="Host ${FQDN}"
if ! grep -q "$SSH_STRING" "$SSH_HOME/config"; then

########## BEGIN
    cat >> "$SSH_HOME/config" <<-EOF

${SSH_STRING}
    HostName ${FQDN}
    User ubuntu
EOF
###

fi

# if the machine doesn't exist, we create it.
if ! incus list --format csv | grep -q "$INCUS_VM_NAME"; then

    # create a base image if needed and instantiate a VM.
    if [ -z "$MAC_ADDRESS_TO_PROVISION" ]; then
        echo "ERROR: You MUST define a MAC Address for all your machines in your project definition."
        echo "INFO: IMPORTANT! You MUST have DHCP Reservations for these MAC addresses. You also need records established the DNS."
        exit 1
    fi

    # TODO ensure we are only GROWING the volume--never shrinking per zfs volume docs.
    BACKUP_DISK_SIZE_GB=
    SSDATA_DISK_SIZE_GB=
    DOCKER_DISK_SIZE_GB=
    if [ "$VIRTUAL_MACHINE" = www ]; then
        if [ "$SKIP_WWW_SERVER" = true ]; then
            exit 0
        fi

        BACKUP_DISK_SIZE_GB="$WWW_BACKUP_DISK_SIZE_GB"
        SSDATA_DISK_SIZE_GB="$WWW_SSDATA_DISK_SIZE_GB"
        DOCKER_DISK_SIZE_GB="$WWW_DOCKER_DISK_SIZE_GB"
    fi

    if [ "$VIRTUAL_MACHINE" = btcpayserver ]; then
        if [ "$SKIP_BTCPAY_SERVER" = true ]; then
            exit 0
        fi

        BACKUP_DISK_SIZE_GB="$BTCPAYSERVER_BACKUP_DISK_SIZE_GB"
        SSDATA_DISK_SIZE_GB="$BTCPAYSERVER_SSDATA_DISK_SIZE_GB"
        DOCKER_DISK_SIZE_GB="$BTCPAYSERVER_DOCKER_DISK_SIZE_GB"
    fi

    SSDATA_VOLUME_NAME=
    BACKUP_VOLUME_NAME=
    if [ "$VIRTUAL_MACHINE" != lnplayserver ]; then
        DOCKER_VOLUME_NAME="$VIRTUAL_MACHINE-docker"
        if ! incus storage volume list ss-base | grep -q "$DOCKER_VOLUME_NAME"; then
            incus storage volume create ss-base "$DOCKER_VOLUME_NAME" --type=block
            incus storage volume set ss-base "$DOCKER_VOLUME_NAME" size="${DOCKER_DISK_SIZE_GB}GB"
        fi

        SSDATA_VOLUME_NAME="$VIRTUAL_MACHINE-ss-data"
        if ! incus storage volume list ss-base | grep -q "$SSDATA_VOLUME_NAME"; then
            incus storage volume create ss-base "$SSDATA_VOLUME_NAME" --type=filesystem
            incus storage volume set ss-base "$SSDATA_VOLUME_NAME" size="${SSDATA_DISK_SIZE_GB}GB"
        fi

        BACKUP_VOLUME_NAME="$VIRTUAL_MACHINE-backup"
        if ! incus storage volume list ss-base | grep -q "$BACKUP_VOLUME_NAME"; then
            incus storage volume create ss-base "$BACKUP_VOLUME_NAME" --type=filesystem
            incus storage volume set ss-base "$BACKUP_VOLUME_NAME" size="${BACKUP_DISK_SIZE_GB}GB"
        fi

    fi


    bash -c "./stub_profile.sh --vm=$VIRTUAL_MACHINE --incus-hostname=$INCUS_VM_NAME --ss-volume-name=$SSDATA_VOLUME_NAME --backup-volume-name=$BACKUP_VOLUME_NAME"

  INCUS_LNPLAYSERVER_IMAGE_NAME="lnplayserver-$DOMAIN_NAME"
  if ! incus image list -q --format csv | grep -q "$INCUS_LNPLAYSERVER_IMAGE_NAME"; then
        script -q -c "incus init -q $DOCKER_BASE_IMAGE_NAME $INCUS_VM_NAME --vm --profile=$INCUS_VM_NAME" /dev/null
    elif [ "$VIRTUAL_MACHINE" = lnplayserver ]; then
        script -q -c "incus init -q $INCUS_LNPLAYSERVER_IMAGE_NAME $INCUS_VM_NAME --vm --profile=$INCUS_VM_NAME" /dev/null
    fi

    # let's PIN the HW address for now so we don't exhaust IP
    # and so we can set DNS internally.
    incus config set "$INCUS_VM_NAME" "volatile.enp5s0.hwaddr=$MAC_ADDRESS_TO_PROVISION"

    if [ "$VIRTUAL_MACHINE" != lnplayserver ]; then
        # attack the docker block device.
        incus storage volume attach ss-base "$DOCKER_VOLUME_NAME" "$INCUS_VM_NAME"
    fi

    # if [ "$VIRTUAL_MACHINE" = btcpayserver ]; then
    #     # attach any volumes
    #     for CHAIN in testnet mainnet; do
    #         for DATA in blocks chainstate; do
    #             MOUNT_PATH="/$CHAIN-$DATA"
    #             incus config device add "$INCUS_VM_NAME" "$CHAIN-$DATA" disk pool=ss-base source="$CHAIN-$DATA" path="$MOUNT_PATH"
    #         done
    #     done
    # fi

    incus start "$INCUS_VM_NAME"
    sleep 15

    bash -c "./wait_for_ip.sh --incus-name=$INCUS_VM_NAME"

    # scan the remote machine and install it's identity in our SSH known_hosts file.
    ssh-keyscan -H "$FQDN" >> "$SSH_HOME/known_hosts"

    if [ "$VIRTUAL_MACHINE" != lnplayserver ]; then
        ssh "$FQDN" "sudo chown ubuntu:ubuntu $REMOTE_DATA_PATH"
        ssh "$FQDN" "sudo chown -R ubuntu:ubuntu $REMOTE_BACKUP_PATH"
    fi

fi