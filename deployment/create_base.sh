#!/bin/bash

set -exu
cd "$(dirname "$0")"

. ./base.sh

bash -c "./stub_profile.sh --incus-hostname=$BASE_IMAGE_VM_NAME"

if incus list -q --project default | grep -q "$BASE_IMAGE_VM_NAME" ; then
    incus delete -f "$BASE_IMAGE_VM_NAME" --project default
fi

# let's download our base image.
if ! incus image list --format csv --columns l --project default | grep -q "$UBUNTU_BASE_IMAGE_NAME"; then
    # copy the image down from canonical.
    incus image copy "images:$BASE_INCUS_IMAGE" "$REMOTE_NAME": --alias "$UBUNTU_BASE_IMAGE_NAME" --public --vm --auto-update --target-project default
fi

# If the VM does exist, then we will delete it (so we can start fresh) 
if incus list --format csv -q --project default | grep -q "$UBUNTU_BASE_IMAGE_NAME"; then
    # if there's no snapshot, we dispense with the old image and try again.
    if ! incus info "$BASE_IMAGE_VM_NAME"  --project default | grep -q "$UBUNTU_BASE_IMAGE_NAME"; then
        incus delete "$BASE_IMAGE_VM_NAME" --force --project default
        ssh-keygen -f "$SSH_HOME/known_hosts" -R "$BASE_IMAGE_VM_NAME"
    fi
else

    if ! incus list --project default | grep -q "$BASE_IMAGE_VM_NAME"; then
        # the base image is ubuntu:22.04.
        script -q -c "incus init -q --profile=$BASE_IMAGE_VM_NAME $UBUNTU_BASE_IMAGE_NAME $BASE_IMAGE_VM_NAME --vm --project default" /dev/null
    fi

    if incus info "$BASE_IMAGE_VM_NAME" --project default | grep -q "Status: STOPPED"; then
        # TODO move this sovereign-stack-base construction VM to separate dedicated IP
        incus config set "$BASE_IMAGE_VM_NAME" --project default
        incus start "$BASE_IMAGE_VM_NAME" --project default
        sleep 30
    fi

    # for CHAIN in mainnet testnet; do
    #     for DATA in blocks chainstate; do
    #         incus storage volume attach ss-base "$CHAIN-$DATA" "$BASE_IMAGE_VM_NAME" "/home/ubuntu/bitcoin/$DATA"
    #     done
    # done

    if incus info "$BASE_IMAGE_VM_NAME" --project default | grep -q "Status: RUNNING"; then

        while incus exec "$BASE_IMAGE_VM_NAME" --project default -- [ ! -f /var/lib/cloud/instance/boot-finished ]; do
            sleep 1
        done

        # ensure the ssh service is listening at localhost
        incus exec "$BASE_IMAGE_VM_NAME" --project default -- wait-for-it -t 100 127.0.0.1:22

        # # If we have any chaninstate or blocks in our SSME, let's push them to the
        # # remote host as a zfs volume that way deployments can share a common history
        # # of chainstate/blocks.
        # for CHAIN in testnet mainnet; do
        #     for DATA in blocks chainstate; do
        #         # if the storage snapshot doesn't yet exist, create it.
        #         if ! incus storage volume list ss-base -q --format csv -c n | grep -q "$CHAIN-$DATA/snap0"; then
        #             DATA_PATH="/home/ubuntu/.ss/cache/bitcoin/$CHAIN/$DATA"
        #             if [ -d "$DATA_PATH" ]; then
        #                 COMPLETE_FILE_PATH="$DATA_PATH/complete"
        #                 if incus exec "$BASE_IMAGE_VM_NAME" -- [ ! -f "$COMPLETE_FILE_PATH" ]; then
        #                     incus file push --recursive --project default "$DATA_PATH/" "$BASE_IMAGE_VM_NAME""$DATA_PATH/"
        #                     incus exec "$BASE_IMAGE_VM_NAME" -- su ubuntu - bash -c "echo $(date) > $COMPLETE_FILE_PATH"
        #                     incus exec "$BASE_IMAGE_VM_NAME" -- chown -R 999:999 "$DATA_PATH/$DATA"
        #                 else
        #                     echo "INFO: it appears as though $CHAIN/$DATA has already been initialized. Continuing."
        #                 fi
        #             fi
        #         fi
        #     done
        # done

        # stop the VM and get a snapshot.
        incus stop "$BASE_IMAGE_VM_NAME" --project default
    fi
    
    incus snapshot create "$BASE_IMAGE_VM_NAME" "$UBUNTU_BASE_IMAGE_NAME" --project default

fi

echo "INFO: Publishing '$BASE_IMAGE_VM_NAME' as image '$DOCKER_BASE_IMAGE_NAME'. Please wait."
incus publish -q --public "$BASE_IMAGE_VM_NAME/$UBUNTU_BASE_IMAGE_NAME" \
                 --project default --alias="$DOCKER_BASE_IMAGE_NAME" \
                 --compression none

echo "INFO: Success creating the base image. Deleting artifacts from the build process."
incus delete -f "$BASE_IMAGE_VM_NAME" --project default

# # now let's get a snapshot of each of the blocks/chainstate directories.
# for CHAIN in testnet mainnet; do
#     for DATA in blocks chainstate; do
#         if ! incus storage volume list ss-base -q --format csv -c n | grep -q "$CHAIN-$DATA/snap0"; then
#             echo "INFO: Creating a snapshot 'ss-base/$CHAIN-$DATA/snap0'."
#             incus storage volume snapshot ss-base --project default "$CHAIN-$DATA"
#         fi
#     done
# done
